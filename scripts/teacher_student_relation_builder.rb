# frozen_string_literal: true

# copy 以下代碼入去 rails console 來原成工作

# 設定 23xhielts.com 學校
puts 'loading 23xhielts.com'
# 找出老師和學生
teacher = GeneralUser.where(email: 'sharon@23xhielts.com').first
students = GeneralUser.where("email like 'f1%@23xhielts.com'")

students.each do |student|
  KgLinker.add_student_relation(teacher:, student:)
end

puts 'loading otisf4a@23cskphc.com'
teacher = GeneralUser.where(email: 'otisf4a@23cskphc.com').first
students = GeneralUser.where("email like 'f4%@23cskphc.com'")

students.each do |student|
  KgLinker.add_student_relation(teacher:, student:)
end
