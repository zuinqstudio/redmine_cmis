class CreateCmisDocuments < ActiveRecord::Migration
  def self.up
    create_table :cmis_documents do |t|
      t.column :project_id, :integer
      t.column :category_id, :integer
      t.column :author_id, :integer
      t.column :title, :string
      t.column :description, :text
      t.column :path, :text
      t.column :created_on, :datetime
      t.column :updated_on, :datetime
    end

    create_table :cmis_attachments do |t|
      t.column :cmis_document_id, :integer, :null => false
      t.column :author_id, :integer
      t.column :filesize, :integer
      t.column :content_type, :string
      t.column :description, :text
      t.column :path, :text
      t.column :created_on, :datetime
      t.column :updated_on, :datetime
    end

    add_index "cmis_documents", ["project_id"], :name => "cmis_documents_project_id"
  end

  def self.down
    drop_table :cmis_documents
    drop_table :cmis_attachments
  end
end
