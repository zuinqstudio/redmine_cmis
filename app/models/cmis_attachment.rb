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

class CmisAttachment < ActiveRecord::Base
  unloadable
  
  include CmisModule
  
  belongs_to :document, :class_name => "CmisDocument", :foreign_key => "cmis_document_id"
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"

  acts_as_activity_provider :type => 'documents',
                            :permission => :view_cmis_documents,
                            :author_key => :author_id,
                            :find_options => {:select => "#{CmisAttachment.table_name}.*", 
                                              :joins => "LEFT JOIN #{CmisDocument.table_name} ON #{CmisDocument.table_name}.id = #{CmisAttachment.table_name}.cmis_document_id " +
                                                        "LEFT JOIN #{Project.table_name} ON #{CmisDocument.table_name}.project_id = #{Project.table_name}.id"}


  validates_presence_of :author
 
  def before_create
  	logger.debug("Creating new document")
    if (self.created_on == nil)
  	 self.created_on = Time.now
    end
    if (self.updated_on == nil)
      self.updated_on = Time.now
    end  	
  	
    if @temp_file && (@temp_file.size > 0) && self.path_archivo && self.nombre_archivo
      begin
    		cmis_connect
        save_document(self.path_archivo, self.nombre_archivo, get_stream_content(@temp_file.path))
      rescue CmisException=>e
        raise e
      rescue Errno::ECONNREFUSED=>e
        raise CmisException.new, l(:unable_connect_cmis)
      end
    end
  end
  
  def before_update
    self.updated_on = Time.now
  end
  
  def before_destroy
    logger.debug("Removing file " + self.path)
    if self.path != "" && self.path_archivo && self.nombre_archivo
      begin
    	 cmis_connect
    	 remove_document(self.path)
      rescue CmisException=>e
        raise e
      rescue Errno::ECONNREFUSED=>e
        raise CmisException.new, l(:unable_connect_cmis)
      end
    end
  end
  
  def file=(incoming_file)
    unless incoming_file.nil?
      @temp_file = incoming_file
      if @temp_file.size > 0
        self.content_type = @temp_file.content_type.to_s.chomp
        if content_type.blank?
          self.content_type = Redmine::MimeType.of(@temp_file.original_filename)
        end
		self.filesize = @temp_file.size
      end
    end
  end
	
  def file
    return @temp_file
  end

  def path_archivo
	 return File.dirname(self.path)
  end

  def nombre_archivo
	 return File.basename(self.path)
  end
  
  def cmis_file
    begin
      cmis_connect
      return read_document(self.path)
    rescue CmisException=>e
      raise e
    rescue Errno::ECONNREFUSED=>e
      raise CmisException.new, l(:unable_connect_cmis)  
    rescue =>e
      raise CmisException.new, e.message
    end
  end
  
  def update_path(newPath)
    self.path = compose_path(newPath, substring_after_last(self.path, "/"))
    self.save
  end
  
  #Static methods
  def self.validar_nombre_fichero(fichero)
    return validar_nombre_cadena(fichero.original_filename)    
  end
  
  def self.validar_nombre_cadena(cadena)
    valido=true
    noValidosDocumento= ['%','?','&',':',';','|','<','>','/',"\+","\\","\'",'¬','£']
    noValidosAdjunto=   ['*','%','?','&',':',';','|','<','>','/',"\+","\\",'¬','£']
    finalNoValidos= ['.',' ']
  
    if cadena==nil #este caso se da cuando se ha incluido un caracter \ al final del nombre
      valido=false
      flash[:error]=l(:error_caracteres_finales)
      flash.discard
    elsif finalNoValidos.include?(cadena[-1].chr) || noValidosAdjunto.include?(cadena[-1].chr) 
      valido=false 
      flash[:error]=l(:error_caracteres_finales)
      flash.discard
    else
      array=cadena.split("")
      array.each do |p|
        if noValidosAdjunto.include?(p)
          valido=false
          flash[:error]=l(:error_caracteres_finales)
          flash.discard
          break
        end
      end
    end
    return valido
  end
  
  def validate
    if self.filesize > Setting.attachment_max_size.to_i.kilobytes
      errors.add(:base, :too_long, :count => Setting.attachment_max_size.to_i.kilobytes)
    end
  end
  
  def self.attach_files(project, document, attachments)
    attached = []
	warnings = []
    if attachments && attachments.is_a?(Hash)
      attachments.each_value do |tmp|
      file = tmp['file']
		  desc = tmp['description']
      next unless file && file.size > 0
		if file && validar_nombre_fichero(file)
		  attachment = CmisAttachment.new()
			attachment.author = User.current
			attachment.description = desc
		  attachment.cmis_document_id = document.id
			attachment.file = file
			#ahora comprobamos que no exista en redmine otro documento con el mismo proyect_id, categoria de documento y titulo
			nombre_archivo = CmisAttachment.get_nombre_si_repetido(file.original_filename, document.path, document)
		  attachment.path = document.path + nombre_archivo;

			begin
				if attachment.save
				    subject = l(:cmis_subject_add_document, :author => User.current, :proyecto => project.name)
				    mensaje = l(:cmis_message_add_document, :author => User.current, :documento => nombre_archivo, :proyecto => project.name)
					CmisMailer::deliver_send_new_document(project.recipients, subject, mensaje) if Setting.notified_events.include?('document_added')
		            attached << attachment
				else
					document.unsaved_attachments ||= []
					document.unsaved_attachments << attachment
				end
		  rescue Errno::ETIMEDOUT
        raise CmisException.new, l(:unable_connect_cmis)   
			rescue CmisException=>e
        raise e
      rescue Errno::ECONNREFUSED=>e
        raise CmisException.new, l(:unable_connect_cmis)
      end
		else
			warnings << l(:error_conexion_cmis)
		end
      end
    end
    {:files => attached, :unsaved => document.unsaved_attachments, :warnings => warnings}
  end
   
  def self.get_nombre_si_repetido(nombre_archivo, path_archivo, document)
  	repetido = CmisAttachment.find(:first, :conditions =>["cmis_document_id= ? and path= ?", document.id.to_s  ,  path_archivo + nombre_archivo])
  	if repetido # si hay un documento ya con ese nombre, le meto el timestamp
  		nombre_archivo = Time.now.to_i.to_s + "_" + nombre_archivo
  	end
  	return sanitize_filename(nombre_archivo)
  end

  def self.sanitize_filename(filename)
    filename.strip.tap do |name|
      # NOTE: File.basename doesn't work right with Windows paths on Unix
      # get only the filename, not the whole path
      name.sub! /\A.*(\\|\/)/, ''
      # Finally, replace all non alphanumeric, underscore
      # or periods with underscore
      name.gsub! /[^\w\.\-]/, '_'
	  name.gsub! 'á', 'a'
	  name.gsub! 'é', 'e'
	  name.gsub! 'í', 'i'
	  name.gsub! 'ó', 'o'
	  name.gsub! 'ú', 'u'
    end
  end   

  def self.normalizar_cadena(texto)
  	temp = texto.downcase.gsub(" ", "_")
  	temp = temp.gsub(".", "estoesunpunto")
  	temp = temp.mb_chars.normalize(:kd).gsub(/[^x00-\x7F]/n, '').to_s
  	temp = temp.gsub("estoesunpunto", ".")
  	return temp
  end
   
  def self.get_max_filesize_mb
	 return 5
  end
  
  def self.get_max_filesize_bytes
	 return (get_max_filesize_mb * 1024 * 1024)
  end
  
  def self.check_size_reached(size)
	 return (size > get_max_filesize_bytes)
  end
  
 end
