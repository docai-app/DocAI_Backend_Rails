# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Essay Gradings Batch Upload API', swagger_doc: 'v1/swagger.json' do
  path '/api/v1/essay_assignments/{essay_assignment_id}/essay_gradings/batch_upload_pdfs' do
    post '批量上传PDF文件并创建作业评分' do
      tags 'EssayGradings'
      consumes 'multipart/form-data'
      produces 'application/json'
      
      parameter name: :essay_assignment_id, in: :path, type: :string, required: true,
                description: '作业的唯一代码'
      
      parameter name: :pdf_files, in: :formData, type: :array, items: { type: :file }, required: true,
                description: 'PDF文件数组，文件名应为学生email（不含.pdf扩展名）'
      
      security [Bearer: {}]
      
      response '201', '成功创建作业评分' do
        description '成功处理PDF文件并创建对应的作业评分记录'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Successfully processed 3 PDF files' },
                 processed_count: { type: :integer, example: 3 },
                 successful_gradings: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid, example: '123e4567-e89b-12d3-a456-426614174000' },
                       student_email: { type: :string, example: 'student@example.com' },
                       student_name: { type: :string, example: '张三' },
                       status: { type: :string, example: 'pending' },
                       created_at: { type: :string, format: 'date-time', example: '2023-10-27T10:00:00.000Z' }
                     }
                   }
                 },
                 not_found_emails: {
                   type: :array,
                   items: { type: :string },
                   example: ['unknown@example.com', 'invalid@example.com'],
                   description: '找不到对应学生的email列表'
                 }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
      
      response '400', '请求参数错误' do
        description '请求参数无效或缺少必要参数'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'No PDF files provided' }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [] }
        
        run_test!
      end
      
      response '401', '未授权' do
        description '用户未认证或JWT Token无效'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'You need to sign in or sign up before continuing.' }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
      
      response '403', '权限不足' do
        description '用户没有权限执行此操作（非教师或管理员）'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'Only teachers and admins can batch upload PDFs' }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
      
      response '404', '作业不存在' do
        description '指定的作业代码不存在'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'EssayAssignment not found' }
               }
        
        let(:essay_assignment_id) { 'INVALID-CODE' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
      
      response '422', '处理失败' do
        description 'PDF文件处理失败，但部分文件可能成功处理'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'Failed to process some PDF files' },
                 processed_count: { type: :integer, example: 1 },
                 errors: {
                   type: :array,
                   items: { type: :string },
                   example: ['Student not found for email: unknown@example.com', 'Could not extract content from PDF for student: invalid@example.com']
                 },
                 successful_gradings: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid },
                       student_email: { type: :string },
                       student_name: { type: :string },
                       status: { type: :string },
                       created_at: { type: :string, format: 'date-time' }
                     }
                   }
                 },
                 not_found_emails: {
                   type: :array,
                   items: { type: :string },
                   example: ['unknown@example.com', 'invalid@example.com']
                 }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
      
      response '500', '服务器内部错误' do
        description '服务器发生意外错误'
        
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, example: 'Internal server error: Something went wrong' }
               }
        
        let(:essay_assignment_id) { 'ASMT-001' }
        let(:pdf_files) { [fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf')] }
        
        run_test!
      end
    end
  end
end
