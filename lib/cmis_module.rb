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

module CmisModule
  
  attr_accessor :client
  
  def cmis_connect      
      begin
        if (@client == nil)
          @client = ActiveCMIS.connect(Setting.plugin_redmine_cmis)
        end
      rescue Errno::ECONNREFUSED
        raise CmisException.new, l(:unable_connect_cmis)
      rescue ActiveCMIS::Error::ObjectNotFound
        raise CmisException.new, l(:repository_not_found)
      rescue ActiveCMIS::HTTPError
        raise CmisException.new, l(:cmis_authentication_failed)
      end
      return true
  end
  
  ###########################
  #   Documents Methods     #
  ###########################
  
  def save_document(path, documentName, contentStream)
    save_document_relative(path, documentName, contentStream, true)
  end
  
  def save_document_relative(path, documentName, contentStream, isRelativePath)    
    # Call save_folder, just in case it doesn't exist
    folder = save_folder_relative(path, isRelativePath)
    
    # Create Cmis document
    docType = @client.type_by_id("cmis:document")
    if (docType.content_stream_allowed == "notallowed")
      docType = @client.type_by_id("File")
    end
    newDocument = docType.new("cmis:name" => documentName)
    newDocument.file(folder)
    newDocument.set_content_stream(:data=>contentStream, :overwrite=>true)
    newDocument.save
    
    folder.reload
  end  
  
  def copy_document(fromPath, toPath)
    copy_document_relative(fromPath, toPath, true)
  end
  
  def copy_document_relative(fromPath, toPath, isRelativePath)
    # Read document content
    content = read_document_relative(fromPath, isRelativePath)
    
    # Save document into destination folder
    save_document_relative(get_path_to_folder(toPath), get_document_name(toPath), content, isRelativePath)    
  end
  
  def move_document(fromPath, toPath)
    move_document_relative(fromPath, toPath, true)
  end
  
  def move_document_relative(fromPath, toPath, isRelativePath)
    # Copy document content
    copy_document_relative(fromPath, toPath, isRelativePath)
    
    # Remove old document
    remove_document_relative(fromPath, isRelativePath)    
  end
  
  def read_document(path)
    return read_document_relative(path, true)
  end
  
  def read_document_relative(path, isRelativePath)
    document = get_document_relative(path, isRelativePath)
    return document.content_stream.get_data[:data]
  end
  
  def get_document(path)
    return get_document_relative(path, true)
  end
  
  def get_document_relative(path, isRelativePath)
    parent = get_folder_relative(get_path_to_folder(path), isRelativePath)
    aux = parent.items.select {|o| o.is_a?(ActiveCMIS::Document) && o.cmis.name == get_document_name(path)}
    return aux.first
  end 
  
  def remove_document(path)
    remove_document_relative(path, true)
  end
  
  def remove_document_relative(path, isRelativePath)
    document = get_document_relative(path, isRelativePath)
    if (document != nil)
      document.destroy
      
      # Update parent folder 
      parentPath = get_path_to_folder(path)
      parentFolder = get_folder_relative(parentPath, isRelativePath)
      parentFolder.reload
    end    
  end
  
  ###########################
  #     Folders Methods     #
  ###########################
  
  def save_folder(path)
    save_folder_relative(path, true)
  end
  
  def save_folder_relative(path, isRelativePath)
    res = nil
    
    if (path == nil or path.empty? or path == "/")
      # Path is root folder
      if (isRelativePath)
        # If the root is relative, keep going to path base
        res = save_folder_relative(Setting.plugin_redmine_cmis['documents_path_base'], false);
      else 
        res = @client.root_folder
      end
      
    elsif (!exists_path_relative(path, isRelativePath))
      # Build path
      parentPath = get_path_to_folder(path);
      
      # Recursively create parent folders
      parent = save_folder_relative(parentPath, isRelativePath);      
      
      # Create the cmis folder
      folderName = get_folder_name(path);
      
      folderType = @client.type_by_id("cmis:folder")
      newFolder = folderType.new("cmis:name" => folderName)
      newFolder.file(parent)
      newFolder.save
    
      # Reload parent
      parent.reload
    
      res = newFolder    
    else 
      res = get_folder_relative(path, isRelativePath)    
    end
  
    # Reload folder content
    res.reload
    
    return res    
  end
  
  def copy_folder(fromPath, toPath)
    copy_folder_relative(fromPath, toPath, true)
  end
  
  def copy_folder_relative(fromPath, toPath, isRelativePath)
    # Create destination folder
    save_folder_relative(toPath, isRelativePath)
    
    # Get source folder
    sourceFolder = get_folder_relative(fromPath, isRelativePath)
    
    # Copy subfolders in folder
    sourceFolder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}.map {|o|
      copy_folder_relative(compose_path(fromPath, o.name), compose_path(toPath, o.name), isRelativePath)
    }
  
    # Remove documents in folder
    sourceFolder.items.select {|o| o.is_a?(ActiveCMIS::Document)}.map {|o|
      copy_document_relative(compose_path(fromPath, o.name), compose_path(toPath, o.name), isRelativePath)
    }
  end
  
  def move_folder(fromPath, toPath)
    move_folder_relative(fromPath, toPath, true)
  end
  
  def move_folder_relative(fromPath, toPath, isRelativePath)
    # Copy document content
    copy_folder_relative(fromPath, toPath, isRelativePath)
    
    # Remove old document
    remove_folder_relative(fromPath, isRelativePath)    
  end
  
  def get_folder(path)
    get_folder_relative(path, true)
  end
  
  def get_folder_relative(path, isRelativePath)
    res = nil
    
    if (path == nil or path.empty? or path == "/")
      # Path is root folder
      if (isRelativePath)
        # If the root is relative, keep going to path base
        res = get_folder_relative(Setting.plugin_redmine_cmis['documents_path_base'], false);
      else
        res = @client.root_folder
      end
      
    else
      # Build path
      parentPath = get_path_to_folder(path);
      
      # Get the immediate parent folder
      parent = get_folder_relative(parentPath, isRelativePath);
      
      if (parent != nil)
        aux = parent.items.select {|o| o.is_a?(ActiveCMIS::Folder) && o.cmis.name == get_folder_name(path)}      
        res = aux.first
      end
      
    end
    
    if (res != nil)
      # Reload folder content
      res.reload
    end
    
    return res
    
  end
  
  def remove_folder(path)
    remove_folder_relative(path, true)
  end
  
  def remove_folder_relative(path, isRelativePath)    
    folder = get_folder_relative(path, isRelativePath)
    
    if (folder != nil)
      # Remove subfolders in folder
      folder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}.map {|o|
        remove_folder_relative(o.cmis.path, isRelativePath)
      }  
    
      # Remove documents in folder
      folder.items.select {|o| o.is_a?(ActiveCMIS::Document)}.map {|o|
        remove_document_relative(compose_path(path, o.name), isRelativePath)
      }
      
      folder.destroy
      
      # Update parent folder 
      parentPath = get_path_to_folder(path)
      parentFolder = get_folder_relative(parentPath, isRelativePath)
      parentFolder.reload
    end    
  end
  
  def exists_path_relative(path, isRelativePath)
    if (get_folder_relative(path, isRelativePath) == nil)
      return false
    else
      return true
    end
  end
  
  def exists_path(path)
    return exists_path_relative(path, true)
  end

  def get_documents_in_folder(path)
    return get_documents_in_folder_relative(path, true)
  end

  def get_documents_in_folder_relative(path, isRelativePath)
    folder = get_folder_relative(path, isRelativePath)
    return folder.items.select {|o| o.is_a?(ActiveCMIS::Document)}
  end

  def get_folders_in_folder(path)
    return get_folders_in_folder_relative(path, true)
  end

  def get_folders_in_folder_relative(path, isRelativePath)
    folder = get_folder_relative(path, isRelativePath)
    return folder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}
  end

  ###########################
  #         Utils           #
  ###########################
  
  def get_path_to_folder(documentUri)
    if documentUri != nil and !documentUri.empty?
      
      if (documentUri.end_with?"/")
        documentUri = substring_before_last(documentUri, "/")
      end
      
      if (documentUri.include?"/")
        return substring_before_last(documentUri, "/")
      else
        return "/"
      end
      
    else
      return ""
    end  
  end
    
  def get_document_name(documentUri)
    if (documentUri != nil and !documentUri.empty?)
      if (!documentUri.include?"/")
        return documentUri
      else
        return substring_after_last(documentUri, "/")
      end
    else
      return ""
    end
  end
  
  def get_folder_name(folderUri)    
    if (folderUri != nil and !folderUri.empty?)      
      if (folderUri.end_with?"/")
        folderUri = substring_before_last(folderUri, "/")
      end
      if (!folderUri.include?"/")
        return folderUri;
      else
        return substring_after_last(folderUri, "/")
      end
    else
      return ""
    end
  end
  
  def substring_before_last(cadena, separador) 
    lastIndex = cadena.rindex(separador)
    return cadena[0, lastIndex]
  end
  
  def substring_after_last(cadena, separador) 
    lastIndex = cadena.rindex(separador)
    if (lastIndex != nil)
      return cadena[lastIndex + 1, cadena.length - 1]
    else
      return ""
    end
  end
  
  def get_stream_content(absolutePath)
    return File.open(absolutePath, "rb") {|io| io.read}
  end
  
  def compose_path(path, documentName)
    if (path.end_with?"/")
      return path + documentName
    else
      return path + "/" + documentName
    end
  end
  
end
