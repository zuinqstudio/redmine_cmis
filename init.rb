# Encoding: UTF-8
# Written by: Signo-Net
# Email: clientes@signo-net.com 
# Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'redmine'
require 'active_cmis' 

Redmine::Plugin.register :redmine_cmis do
	name 'Redmine Cmis Plugin'
	author 'Signo-Net'
	description 'Storage proyect files on your Cmis server'
	version '0.0.4'
	url 'http://www.signo-net.com/downloads/'
	author_url 'http://www.signo-net.com'

	menu :project_menu, :cmis, { :controller => 'cmis', :action => 'index' }, :caption => 'Cmis', :after => :documents, :param => :project_id

	settings :default => {
    'server_url' => 'http://localhost:8080/alfresco/service/cmis',
    'repository_id' => 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
		'server_login' => 'user',
		'server_password' => 'password',
		'documents_path_base' => 'REDMINE'
	}, :partial => 'settings/cmis_settings'

	project_module :cmis do
		permission :view_cmis_documents, {:cmis => [:index, :show, :download]}, :public => true
		permission :manage_cmis_documents, :cmis => [:new, :edit, :destroy, :destroy_attachment, :synchronize, :synchronize_document, :import, :prepare_import, :add_attachment]
	end
	
    raise 'active_cmis library not installed' unless defined?(ActiveCMIS)

end
