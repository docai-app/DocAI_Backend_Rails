# frozen_string_literal: true

# == Schema Information
#
# Table name: schools
#
#  id            :uuid             not null, primary key
#  name          :string           not null
#  code          :string           not null
#  status        :integer          default("active")
#  address       :string
#  contact_email :string
#  contact_phone :string
#  timezone      :string
#  meta          :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_schools_on_code  (code) UNIQUE
#  index_schools_on_name  (name) UNIQUE
#
require 'test_helper'

class SchoolTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'normalizes enabled student login settings' do
    school = build_school(
      student_login_enabled: true,
      student_login_slug: ' Demo-School ',
      student_email_domain: ' @Students.Demo.EDU '
    )

    assert school.save
    assert_equal 'demo-school', school.student_login_slug
    assert_equal 'students.demo.edu', school.student_email_domain
  end

  test 'requires slug and email domain when student login is enabled' do
    school = build_school(student_login_enabled: true)

    assert_not school.valid?
    assert school.errors.added?(:student_login_slug, :blank)
    assert school.errors.added?(:student_email_domain, :blank)
  end

  test 'rejects invalid slug and email domain' do
    school = build_school(
      student_login_enabled: true,
      student_login_slug: 'invalid_slug',
      student_email_domain: 'https://school.example.com/path'
    )

    assert_not school.valid?
    assert school.errors[:student_login_slug].present?
    assert school.errors[:student_email_domain].present?
  end

  test 'requires a unique student login slug' do
    build_school(
      student_login_enabled: true,
      student_login_slug: 'shared-login',
      student_email_domain: 'first.example.edu'
    ).save!
    duplicate = build_school(
      student_login_enabled: true,
      student_login_slug: 'SHARED-LOGIN',
      student_email_domain: 'second.example.edu'
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:student_login_slug].present?
  end

  test 'allows disabled student login without settings' do
    school = build_school(student_login_enabled: false)

    assert school.valid?
  end

  test 'disables student login by default' do
    school = build_school

    school.save!

    assert_not school.student_login_enabled
  end

  private

  def build_school(attributes = {})
    School.new({
      name: "School #{SecureRandom.hex(5)}",
      code: "SCHOOL_#{SecureRandom.hex(5).upcase}",
      status: :active,
      meta: {}
    }.merge(attributes))
  end
end
