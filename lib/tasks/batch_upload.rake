namespace :batch_upload do
  desc "Upload directories to auzre(no ocr)"
  

  def parent_folder(file_path)
    parent_dir_name = File.basename(File.dirname(file_path))
    parent_folder = Folder.find_or_create_by(name: parent_dir_name)
  end

  task :create_folders => :environment do

    # 開一個 admin 帳號, 作為最權限
    user = User.find_or_create_by(name: "chyb_admin")

    # 開好 d folder
    root_folder = Folder.find_or_create_by(name: "人力資源部", user: user)

    Dir['/Users/sin/Downloads/人力資源部/**/*'].each do |f|
      if File.directory?(f)
        
        puts "#{f} ... "
        folder_name = File.basename(f)
        parent_folder(f).children.find_or_create_by name: folder_name, user: user

      end
    end
  end

  task :documents => :environment do
    Dir['/Users/sin/Downloads/人力資源部/**/*'].each do |f|
      next if File.directory?(f)

      # 先睇下條 record 係咪已經存在，即係已經 upload 左未
      next if Document.where(upload_local_path: f).first.present?
      puts "Uploading #{f} .. "
      folder = parent_folder(f)
      data = File.open(f, "rb")
      doc = Document.new(folder_id: folder.id, status: "uploaded", upload_local_path: f)
      doc.file.attach(io: data, filename: File.basename(f), content_type: "application/pdf")
      doc.save
      # binding.pry
      break
    end
  end

end