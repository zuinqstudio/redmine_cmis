# Encoding: UTF-8
# Written by: Signo-Net
# Email: clientes@signo-net.com 
# Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

class CmisMailer < ActionMailer::Base
   def send_new_document(recipients, subject, mensaje)
	  #@from = from
	  @recipients = recipients     
	  @sent_on = Time.now
	  @subject = subject
	  @body = mensaje
      @content_type = "text/html"
   end
end  

class CmisController < ApplicationController
  include CmisModule
  
  default_search_scope :documents
  before_filter :find_project, :only => [:index, :new, :synchronize_attachment, :check_attachments_sync, :check_new_attachments]
  before_filter :find_document, :only => [:show, :destroy, :edit, :add_attachment, :check_attachments_sync, :check_new_attachments]
  before_filter :find_attachment, :only => [:destroy_attachment, :download_attachment]
  
  helper :attachments

  unloadable

  def index
    @sort_by = %w(category date title author).include?(params[:sort_by]) ? params[:sort_by] : 'category'
  	@documents = CmisDocument.find :all, :conditions => ["project_id=" + @project.id.to_s]
  
  	case @sort_by
	    when 'date'
	      @grouped = @documents.group_by {|d| d.created_on.to_date }
	    when 'title'
	      @grouped = @documents.group_by {|d| d.title.first.upcase}
	    when 'author'
	      @grouped = @documents.group_by {|d| d.author.name.upcase}
	    else
	      @grouped = @documents.group_by(&:category)
    end
    @document = @project.documents.build
    
    render :layout => false if request.xhr?
  end
  
  def new
   @document = CmisDocument.new(params[:document])
   @document.author = User.current
   @document.project_id = @project.id
   # Check the path doesn't exists
   @document.path = CmisDocument.document_category_path(@document.project, @document.category, @document)
   if CmisDocument.check_repeated(@document)
	  flash[:warning] = l(:documento_repetido)
	  redirect_to :action => 'index', :project_id => @project
   else
	   # Save the document
     begin
  	   if request.post? and @document.save	
  	      attachments = CmisAttachment.attach_files(@project, @document, params[:attachments])
  	      render_attachment_warning_if_needed(@document)
  		  
    		  attachments[:warnings].each{|warning|
    			flash[:warning]=warning
    		  }
    		  
    		  subject = l(:cmis_subject_add_document, :author => User.current, :proyecto => @project.name)
    		  mensaje = l(:cmis_message_add_document, :author => User.current, :documento => @document.title, :proyecto => @project.name)
    		  CmisMailer::deliver_send_new_document(@project.recipients, subject, mensaje) if Setting.notified_events.include?('document_added')
    	      
    		  flash[:notice] = l(:notice_successful_create)
    	      redirect_to :action => 'index', :project_id => @project
  	    end
     rescue CmisException=>e
       flash[:error] = e.message
       flash.discard
     end
   end
  end
  
  def show
    @attachments = @document.attachments
  end
  
  def add_attachment
    begin
      attachments = CmisAttachment.attach_files(@project, @document, params[:attachments])
      render_attachment_warning_if_needed(@document)
  
      #Mailer.deliver_attachments_added(attachments[:files]) if attachments.present? && attachments[:files].present? && Setting.notified_events.include?('document_added')
      redirect_to :action => 'show', :id => @document
    rescue CmisException=>e
       flash[:error] = e.message
       redirect_to :action => 'show', :id => @document
    end
  end
  
  def edit
    @categories = DocumentCategory.all
    begin
      if request.post?    	      	  
    	  if @document.update_attributes(params[:document])
          flash[:notice] = l(:notice_successful_update)
          redirect_to :action => 'show', :id => @document
        end
      end
      
    rescue CmisException=>e
      flash[:error] = e.message
      flash.discard
    end
  end

  def destroy
  	begin
  		if @document.destroy
  			flash[:notice] = l(:notice_successful_delete)
  			redirect_to :action => 'index', :project_id => @project
  		end
  	rescue CmisException=>e
      flash[:error] = e.message
      redirect_to  :action => 'show', :id => @document
    end
  end
  
  def download_attachment
  	begin
  		fichero = @attachment.cmis_file
  		if (fichero != nil)
        filename = @attachment.nombre_archivo
  		  send_data(fichero, :type=> @attachment.content_type, :filename =>filename, :disposition =>'attachment')
  		else
        flash[:warning]=l(:error_fichero_no_enco_cmis)
      redirect_to  :action => 'show', :id => @document
      end
  	rescue CmisException=>e
  		flash[:error] = e.message
  		redirect_to :action => 'show', :id => @document  	
  	end
  end

  def destroy_attachment
    begin
  		attachment = CmisAttachment.find(params[:id])
  		if attachment.destroy
  			flash[:notice] = l(:notice_successful_delete)
  			redirect_to  :action => 'show', :id => @document
  		end
	  rescue CmisException=>e
      flash[:error] = e.message
      redirect_to  :action => 'show', :id => @document
    end
  end
  
  def check_new_attachments
    attachments = @document.attachments
    
    begin
      cmis_connect
      repositoryDocuments = get_documents_in_folder(@document.path)
      repositoryDocuments.each{|repositoryDoc|
        # Check if the cmisDocument is not mapped on redmine
        found = false
        attachments.each{|att|          
          if (att.nombre_archivo == repositoryDoc.cmis.name)
            found = true
            break
          end
        }
        if (!found)
          newAtt = map_repository_doc_to_redmine_att(repositoryDoc)
          newAtt.save
          attachments.push(newAtt)
        end
      }
    
    rescue Errno::ECONNREFUSED=>e
      flash[:error] = l(:unable_connect_cmis)
    end
    
    render :partial => 'links', :locals => {:attachments => attachments}
  end
  
  def check_attachments_sync
    attachments = @document.attachments
    
    begin
      cmis_connect
      attachments.each{|attachment|      
        repositoryDocument = get_document(attachment.path)
        if (!repositoryDocument)
          # Document deleted on CMIS ECM
          attachment.dirty = true
        else
          # Check update date
          redmineTime = attachment.updated_on
          redmineDate = DateTime.parse(redmineTime.to_s)
          
          repositoryDate = repositoryDocument.cmis.lastModificationDate
          repositoryTime = Time.parse(repositoryDate.to_s)
          
          diffInSeconds = repositoryDate - redmineDate
          diffInSeconds *= 1.days
          
          if (diffInSeconds > 60)
            attachment.dirty = true    
          end
        end
      }
    rescue Errno::ECONNREFUSED=>e
      flash[:error] = l(:unable_connect_cmis)
    end
        
    render :partial => 'links', :locals => {:attachments => attachments} 
  end
  
  def synchronize_attachment
    attachment = CmisAttachment.find(params[:id])
    
    begin
      cmis_connect
      repositoryDocument = get_document(attachment.path)
      
      if (!repositoryDocument)
        # Document deleted on CMIS ECM
        attachment.deleted = true
        attachment.dirty = false        
        attachment.destroy
        attachment = nil
        
      else
        # Updated
        attachment.filesize = repositoryDocument.cmis.contentStreamLength
        attachment.save
        attachment.dirty = false
      end      
      
    rescue Errno::ECONNREFUSED=>e
      flash[:error] = l(:unable_connect_cmis)
    end
        
    render :partial => 'attachment', :locals => {:attachment => attachment}    
  end
 
  private
  
  def map_repository_doc_to_redmine_att(document)
    attachment = CmisAttachment.new
    
    attachment.filesize = document.cmis.contentStreamLength
    attachment.content_type = document.cmis.contentStreamMimeType
    attachment.description = ''
    attachment.path = @document.path + document.cmis.name
    attachment.created_on = document.cmis.creationDate
    attachment.updated_on = document.cmis.lastModificationDate
    attachment.author = User.current
    attachment.cmis_document_id = @document.id
    
    return attachment
  end
  
  def map_repository_folder_to_redmine_doc(folder, category)
    document = CmisDocument.new
    
    document.project_id = @project.id
    document.category_id = category.id
    document.autor_id = User.current
    document.title = folder.cmis.name
    document.path = CmisDocument.document_category_path(@project, category, document)
    document.created_on = folder.cmis.creationDate
    document.updated_on = folder.cmis.lastModificationDate
    document.description = ''
    
    return document
  end
  
  def find_project
	@project = Project.find(params[:project_id])
	rescue ActiveRecord::RecordNotFound
		render_404
  end
  
  def find_document
     @document = CmisDocument.find(params[:id])
     @project = Project.find(@document.project_id)     
  rescue ActiveRecord::RecordNotFound
     render_404
  end
  
  def find_attachment
     @attachment = CmisAttachment.find(params[:id])
     @document = CmisDocument.find(@attachment.cmis_document_id)
     @project = Project.find(@document.project_id)     
  rescue ActiveRecord::RecordNotFound
     render_404
  end

  
end
