# README

### 註冊一個號
curl -XPOST -H "Content-Type: application/json" -d '{ "user": { "email": "myemail@email.com", "password": "mypassword" } }' http://localhost:3000/users

### Login
curl -XPOST -i -H "Content-Type: application/json" -d '{ "user": { "email": "myemail@email.com", "password": "mypassword" } }' http://localhost:3000/users/sign_in

### 加角色
user = User.first
user.add_role :admin

### 減角色
user = User.first
user.remove_role :admin

### 檢查是否角色
user = User.first
user.has_role? :admin

### 為物件打 tag / labels
https://github.com/mbleigh/acts-as-taggable-on

doc = Document.first
doc.label_list = 'label 1, label 2'
doc.save

doc.labels => ["label 1" , "label 2"]


### create document
curl -XPOST -H "Content-Type: application/json" -d '{ "document": { "name": "未命名文件" } }' http://localhost:3000/api/v1/documents

response: 
  {"data":{"id":"63b1283e-f18c-412f-b8e0-d7e6034e5ffc","name":"未命名文件","storage_url":null,"status":"pending","content":null,"created_at":"2022-07-09T00:34:41.724Z","updated_at":"2022-07-09T00:34:41.724Z"}}% 

###  show document
curl -XGET -H "Content-Type: application/json" http://localhost:3000/api/v1/document/63b1283e-f18c-412f-b8e0-d7e6034e5ffc


### approval
curl -XPOST -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI4YTAyNmJiOC0wMWVmLTQyMzMtODk4Yi1jOWEzNGY2ZDRmMjAiLCJzY3AiOiJ1c2VyIiwiYXVkIjpudWxsLCJpYXQiOjE2NTczMjk2NDIsImV4cCI6MTY1ODYyNTY0MiwianRpIjoiMjliYzE2YjYtMjBmNC00NjQ5LThlZTUtMjYyMzRjMDliMWU0In0.IVaCnEDMmekg1TbmJp9uCSdvMtvCmdC1NCpGKUzPigo" -H "Content-Type: application/json" -d '{"status": "rejected"}' http://localhost:3000/api/v1/documents/63b1283e-f18c-412f-b8e0-d7e6034e5ffc/approval


User.last.approval_documents => [docs]
Document.waiting_approve => [docs]
Document.approved => [docs]

User.last.approval_documents == Document.approved.where(approval_user: User.last)