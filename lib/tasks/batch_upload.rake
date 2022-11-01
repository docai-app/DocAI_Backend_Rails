namespace :batch_upload do
  desc "Upload directories to auzre(no ocr)"

  def parent_folder(file_path)
    parent_dir_name = File.basename(File.dirname(file_path))
    parent_folder = Folder.find_or_create_by(name: parent_dir_name)
  end

  def upload_file(file_name, blob_data)
    blob_client = Azure::Storage::Blob::BlobService

    account_name = "m2mda"
    account_key = ENV["AZURE_STORAGE_ACCESS_KEY"]

    blob_client = Azure::Storage::Blob::BlobService.create(
      storage_account_name: account_name,
      storage_access_key: account_key,
    )

    container_name = ENV["AZURE_STORAGE_CONTAINER"]
    # file_name = "Pic_1758"
    # blob_data = File.open("/Users/sin/Downloads/人力資源部/僱員收入聲名書/Pic_1758.pdf", "rb")
    blob_name = file_name + "_" + SecureRandom.uuid + ".pdf"
    blob_name.downcase!

    blob_client.create_block_blob(container_name, blob_name, blob_data, content_type: "application/pdf")
    blob_client.get_blob_properties(container_name, blob_name)

    return "https://#{account_name}.blob.core.windows.net/#{container_name}/#{blob_name}"
  end

  task :create_folders => :environment do

    # 開一個 admin 帳號, 作為最權限
    user = User.find_or_create_by(email: "vivi.long@chyb.com")

    # 開好 d folder
    root_folder = Folder.find_or_create_by(name: "建業文件", user: user)

    Dir["/Users/chonwai/Downloads/建業文件/**/*"].each do |f|
      if File.directory?(f)
        puts "#{f} ... "
        folder_name = File.basename(f)
        parent_folder(f).children.find_or_create_by name: folder_name, user: user
      end
    end
  end

  task :create_folders_on_root => :environment do
    user = User.find_or_create_by(email: "vivi.long@chyb.com")

    Dir["/Users/chonwai/Downloads/建業文件/**/*"].each do |f|
      if File.directory?(f)
        puts "#{f} ... "
        folder_name = File.basename(f)
        Folder.find_or_create_by(name: folder_name, user: user)
      end

    end
  end
  
  task :documents => :environment do
    user = User.find_or_create_by(email: "vivi.long@chyb.com")

    Dir["/Users/chonwai/Downloads/建業文件/**/*"].each do |f|
      next if File.directory?(f)

      # 先睇下條 record 係咪已經存在，即係已經 upload 左未
      next if Document.where(upload_local_path: f).first.present?
      puts "Uploading #{f} .. "
      folder = parent_folder(f)
      puts "Folder: #{folder.name}"
      data = File.open(f, "rb")
      doc = Document.new(folder_id: folder.id, status: "uploaded", upload_local_path: f, name: File.basename(f))
      # doc.file.attach(io: data, filename: File.basename(f), content_type: "application/pdf")
      doc.storage_url = upload_file(File.basename(f), data)
      puts "Storage URL: #{doc.storage_url}"
      doc.status = :uploaded
      doc.user_id = user.id
      doc.save
      puts "Done #{f} .. "
      # binding.pry
    end
  end

  # rake batch_upload:documents_with_tag tag_id=xxx
  task :documents_with_tag, [:folder_id, :tag_id] => :environment do |task, args|
    tag_id = args[:tag_id]
    folder_id = args[:folder_id]
    puts "Folder ID: #{folder_id}"
    puts "Tag ID: #{tag_id}"
    Dir["/Users/chonwai/Downloads/建業文件/**/*"].each do |f|
      next if File.directory?(f)

      # 先睇下條 record 係咪已經存在，即係已經 upload 左未
      # next if Document.where(upload_local_path: f).first.present?
      # puts "Uploading #{f} .. "
      # folder = parent_folder(f)
      # puts "Folder: #{folder.name}"
      # data = File.open(f, "rb")
      # doc = Document.new(folder_id: folder.id, status: "uploaded", upload_local_path: f, name: File.basename(f))
      doc = Document.where(folder_id: folder_id).where(status: "ready").first
      doc.label_ids = tag_id
      puts "Done Tag ID: #{doc.label_ids}"
      doc.status = :confirmed
      doc.save
    end
    puts "Done"
  end
end
