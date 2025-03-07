module SchoolConstants
  REGIONS = {
    'hk' => '香港',
    'mo' => '澳門'
  }.freeze

  SCHOOL_TYPES = {
    'hk' => {
      'primary' => '小學',
      'secondary' => '中學',
      'kindergarten' => '幼稚園',
      'international' => '國際學校',
      'college' => '大專院校'
    },
    'mo' => {
      'primary' => '小學',
      'secondary' => '中學',
      'kindergarten' => '幼稚園',
      'international' => '國際學校',
      'vocational' => '職業技術學校',
      'college' => '大專院校'
    }
  }.freeze

  CURRICULUM_TYPES = {
    'hk' => {
      'local' => '本地課程',
      'ib' => 'IB課程',
      'ap' => 'AP課程',
      'igcse' => 'IGCSE課程',
      'custom' => '自定義課程'
    },
    'mo' => {
      'local' => '本地課程',
      'ib' => 'IB課程',
      'ap' => 'AP課程',
      'portuguese' => '葡文課程',
      'chinese' => '中文課程',
      'custom' => '自定義課程'
    }
  }.freeze

  ACADEMIC_SYSTEMS = {
    'hk' => {
      '6_3_3' => '6+3+3制',
      '6_6' => '6+6制',
      'custom' => '自定義學制'
    },
    'mo' => {
      '6_3_3' => '6+3+3制',
      '6_6' => '6+6制',
      '15_years' => '十五年一貫制',
      'custom' => '自定義學制'
    }
  }.freeze

  TIMEZONE_BY_REGION = {
    'hk' => 'Asia/Hong_Kong',
    'mo' => 'Asia/Macau'
  }.freeze

  ACADEMIC_YEAR_DEFAULTS = {
    'mo' => {
      start_month: 9,
      end_month: 8
    },
    'hk' => {
      start_month: 9,
      end_month: 8
    }
  }.freeze
end
