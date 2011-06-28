class AttachmentDirtyColumn < ActiveRecord::Migration
  def self.up
    add_column :cmis_attachments, :dirty, :boolean, :default => false
    add_column :cmis_attachments, :deleted, :boolean, :default => false
  end

  def self.down
    remove_column :cmis_attachments, :dirty
    remove_column :cmis_attachments, :deleted
  end
end
