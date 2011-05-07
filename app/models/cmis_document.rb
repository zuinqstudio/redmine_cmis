# Encoding: UTF-8
# Written by: Signo-Net
# Email: clientes@signo-net.com 
# Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'pp'
require 'rubygems'     
require 'active_cmis' 

class CmisException < RuntimeError
  def initialize
    super
  end
end

class CmisDocument < ActiveRecord::Base
  unloadable
  
  include CmisModule
  
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"
  belongs_to :category, :class_name => "DocumentCategory", :foreign_key => "category_id"
  belongs_to :project

  acts_as_searchable :columns => ['title', "#{table_name}.title"], :include => :project

  validates_presence_of :project, :title, :category
  validates_length_of :title, :maximum => 60 

  attr_accessor :unsaved_attachments
  after_initialize :initialize_unsaved_attachments
  
  def before_save
  end
  
  def before_create
  	logger.debug("Creating new document")
  	self.created_on = Time.now
  	self.updated_on = Time.now
  	self.path = CmisDocument.document_category_path(self.project, self.category, self)
    
    begin
      cmis_connect
      save_folder(path)
    rescue CmisException=>e
      raise e
    rescue Errno::ECONNREFUSED=>e
      raise CmisException.new, l(:unable_connect_cmis)
    end
  end
  
  def before_update
  	logger.debug("Updating document")
  	self.updated_on = Time.now
  	#Miramos si ha cambiado la categoria o el nombre para mover la carpeta
  	documento_guardado =  CmisDocument.find(self.id)
  	if self.category_id != documento_guardado.category_id || self.title != documento_guardado.title
  		logger.debug("Document changed")
  		path_archivo = CmisDocument.document_category_path(self.project, self.category, self);

      begin
  		  cmis_connect
  			move_folder(self.path , path_archivo)
  			self.path = path_archivo;
        
        # Update attachments paths
        self.attachments.each{|attachment|
          attachment.update_path(path)
        }
        
  		rescue CmisException=>e
        raise e
      rescue Errno::ECONNREFUSED=>e
        raise CmisException.new, l(:unable_connect_cmis)
      end
  	else
  		logger.debug("Document didn't change")
  	end
  end
  
  def before_destroy
  	logger.debug("Removing documents from: " + self.title)
    begin
      cmis_connect
  		logger.debug("Removing folder")
  		remove_folder(self.path)
  		self.attachments.each{|attachment|
  	    # Clear attachment route, the file it's been destroyed with the folder
  		  attachment.path = ""
  		  attachment.destroy
      }
    rescue CmisException=>e
      raise e
    rescue Errno::ECONNREFUSED=>e
      raise CmisException.new, l(:unable_connect_cmis)
    end
  end
 
  def initialize_unsaved_attachments
    @unsaved_attachments ||= []
  end
  
  def attachments
    return CmisAttachment.find(:all, :conditions => ["cmis_document_id=" + self.id.to_s] , :order => "created_on DESC")
  end
  
  def self.category_path(project, category)
    return "/" + CmisAttachment.sanitize_filename(project.identifier) + "/" + CmisAttachment.sanitize_filename(category.name) + "/"
  end
  
  def self.document_category_path(project, category, document)
    return category_path(project, category) + CmisAttachment.sanitize_filename(document.title) + "/"
  end
  
  def self.check_repeated(document)
    repeated = CmisDocument.find(:first, :conditions =>["path= ?", document.path])
    if repeated
      return true
    else
      return false
    end
  end

 end
