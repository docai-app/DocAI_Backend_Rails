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