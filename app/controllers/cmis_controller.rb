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
  before_filter :find_project, :only => [:index, :new, :synchronize, :import]
  before_filter :find_document, :only => [:show, :destroy, :edit, :add_attachment, :synchronize_document]
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
  
  def synchronize
  	@elementos = {}
  	categories = DocumentCategory.find :all
  	doc = CmisDocument.new()
  	total_a_actualizar = 0
  	
  	categories.each {|category|
  		begin
  			# Load documents for each category
  			i = 0
  			category_path = CmisDocument.category_path(@project, category);
        cmis_connect
  			subfolders = get_folders_in_folder(category_path)
  			sql_in = "";
  			cmis_folders = []

  			# Check new and deleted contents
  			if subfolders != nil
  				subfolders.each {|fold|
  					path = fold.cmis.path + "/"
  					cmis_folders[i] = {"P" => path}
  					if sql_in != ""
  						sql_in += "','"
  					end
  					sql_in += path
  					i = i + 1
  				}
  			end
        
        # Count deleted folders
  			deleted = CmisDocument.find :all, :conditions =>["project_id= ? and category_id= ? and path not in('" + sql_in + "')", @project.id.to_s , category.id.to_s]
  		
        # Count new folders
  			i = 0
  			newFolders = []
  			cmis_folders.each {|cmis|
  				exists = CmisDocument.find(:first, :conditions =>["path= ?", cmis["P"]])
  				if !exists
  					newFolders[i] = {"P" => File.basename(cmis["P"])}
  					i = i + 1
  				end
  			}
  			@elementos[category] = {"E"=> deleted, "N"=> newFolders}
  			total_a_actualizar += newFolders.length + deleted.length
		
  		rescue Errno::ETIMEDOUT
  			flash[:warning]=l(:error_conexion_cmis)
  		rescue CmisException=>e
  			flash[:warning]=e.message
  		end
  	}
  
  	if total_a_actualizar == 0
  		flash[:warning]=l(:label_no_enco_ficheros_sincronizar)
  		redirect_to  :action => 'index', :project_id => @project
  	end
  end
  
  def import
    if request.post?
	  category = DocumentCategory.find(params[:category])
	  path_archivo = CmisDocument.category_path(@project, category) + "/";
	  nombre_archivo = CmisAttachment.sanitize_filename(params[:document][:title])
      @document = CmisDocument.new(params[:document])
      @document.author = User.current
	  @document.category_id = category.id
	  @document.project_id = @project.id
	  @document.path = path_archivo + nombre_archivo;
	  #Si el nombre del archivo es diferente al original, tenemos que renombrarlo en el cmis
	  if params[:nuevo] != nombre_archivo	
		@document.cmis_move(path_archivo + params[:nuevo], path_archivo + nombre_archivo)
	  end

	  if @document.save
		  #Tenemos que sincronizar todos los archivos de este documento
			begin
				#Tenemos que recuperar de cmis por cada category, los ficheros que hay
				metadatos = @document.cmis_metadatos(@document.path)
				#Con los ficheros recuperados comprobamos los que tenemos, los que se han borrado y los nuevos
				if metadatos["contents"] != nil
					metadatos["contents"].each {|fichero|
						if fichero["bytes"] > 0
						    attachment = CmisAttachment.new()
							attachment.author = User.current
							attachment.description = ""
						    attachment.cmis_document_id = @document.id
						    attachment.path = fichero["path"];
							attachment.content_type = Redmine::MimeType.of(File.basename(attachment.path))
							attachment.filesize = fichero["bytes"]
							attachment.save
						end
					}
				end
				
			rescue Errno::ETIMEDOUT
				flash[:warning]=l(:error_conexion_cmis)
			rescue CmisException
				flash[:warning]=l(:error_conexion_cmis)
			end
		  #Muestro el aviso
	      flash[:notice] = l(:notice_successful_create)
	      redirect_to :action => 'synchronize', :project_id => @project
	  end
    end
  end

  def synchronize_document
	begin
		#Tenemos que recuperar de cmis por cada category, los ficheros que hay
		category = DocumentCategory.find(@document.category_id)
		category_path = CmisDocument.document_category_path(@project, category, @document);
		metadatos = @document.cmis_metadatos(category_path)
		sql_in = "";
		documentos_cmis = []
		#Con los ficheros recuperados comprobamos los que tenemos, los que se han borrado y los nuevos
		if metadatos["contents"] != nil
			metadatos["contents"].each {|fichero|
				documentos_cmis << {"P" => fichero["path"], "S" => fichero["bytes"]}
				if sql_in != ""
					sql_in += "','"
				end
				sql_in += fichero["path"]
			}
		end
		#Los documentos eliminados de cmis se puede hacer con un sql
		eliminados = 0
		para_eliminar = CmisAttachment.find :all, :conditions =>["cmis_document_id= ? and path not in('" + sql_in + "')", @document.id.to_s]
		para_eliminar.each {|doc|
			if doc.destroy
			  eliminados = eliminados + 1
			end
		}
		
		#Los documentos añadidos a cmis hay que hacerlo uno a uno
		anadidos = 0
		documentos_cmis.each {|cmis|
			existe = CmisAttachment.find(:first, :conditions =>["path= ?", cmis["P"]])
			if !existe && cmis["S"] > 0
				attachment = CmisAttachment.new()
				attachment.author = User.current
				attachment.description = ""
				attachment.cmis_document_id = @document.id
				attachment.path = cmis["P"];
				attachment.content_type = Redmine::MimeType.of(File.basename(attachment.path))
				attachment.filesize = cmis["S"]
				if attachment.save
				  anadidos = anadidos + 1
				end
			end
		}

		flash[:notice]=l(:documento_sincronizado, :anadidos => anadidos, :eliminados => eliminados)
		redirect_to  :action => 'show', :id => @document

	rescue Errno::ETIMEDOUT
		flash[:warning]=l(:error_conexion_cmis)
	rescue CmisException
		flash[:warning]=l(:error_conexion_cmis)
	end
  end
 
  private
     
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
