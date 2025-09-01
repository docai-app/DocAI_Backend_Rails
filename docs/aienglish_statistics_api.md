# AI English Statistics API Documentation

## Overview
This API provides comprehensive statistics for AI English users, including role distribution and feature usage analytics.

## Endpoint
```
GET /api/admin/v1/general_users/aienglish/statistics
```

## Authentication
- Requires admin authentication
- Include admin authentication headers

## Request
- Method: GET
- No parameters required
- Content-Type: application/json

## Response Format

### Success Response (200 OK)
```json
{
  "success": true,
  "statistics": {
    "role_distribution": {
      "teacher_count": 25,
      "student_count": 120,
      "unknown_count": 3,
      "total_count": 148
    },
    "feature_usage": {
      "by_role": {
        "teacher": {
          "essay": 20,
          "comprehension": 22,
          "speaking_essay": 15,
          "speaking_conversation": 18,
          "sentence_builder": 12,
          "speaking_pronunciation": 16
        },
        "student": {
          "essay": 85,
          "comprehension": 78,
          "speaking_essay": 65,
          "speaking_conversation": 95,
          "sentence_builder": 55,
          "speaking_pronunciation": 72
        }
      },
      "total": {
        "essay": 105,
        "comprehension": 100,
        "speaking_essay": 80,
        "speaking_conversation": 113,
        "sentence_builder": 67,
        "speaking_pronunciation": 88
      }
    },
    "usage_percentage": {
      "teacher": {
        "essay": 80.0,
        "comprehension": 88.0,
        "speaking_essay": 60.0,
        "speaking_conversation": 72.0,
        "sentence_builder": 48.0,
        "speaking_pronunciation": 64.0
      },
      "student": {
        "essay": 70.83,
        "comprehension": 65.0,
        "speaking_essay": 54.17,
        "speaking_conversation": 79.17,
        "sentence_builder": 45.83,
        "speaking_pronunciation": 60.0
      },
      "total": {
        "essay": 71.62,
        "comprehension": 68.24,
        "speaking_essay": 54.6,
        "speaking_conversation": 77.1,
        "sentence_builder": 45.68,
        "speaking_pronunciation": 60.07
      }
    }
  },
  "metadata": {
    "features_list": [
      "essay",
      "comprehension",
      "speaking_essay", 
      "speaking_conversation",
      "sentence_builder",
      "speaking_pronunciation"
    ],
    "generated_at": "2025-01-01T12:00:00Z",
    "total_analyzed_users": 148
  }
}
```

### Error Response (500 Internal Server Error)
```json
{
  "success": false,
  "error": "Error message description",
  "details": "Error occurred while generating AI English statistics"
}
```

## Response Fields

### statistics.role_distribution
- `teacher_count`: Number of users with teacher role
- `student_count`: Number of users with student role  
- `unknown_count`: Number of users with unknown/missing role
- `total_count`: Total number of analyzed users

### statistics.feature_usage.by_role
- `teacher`: Feature usage counts for teachers
- `student`: Feature usage counts for students

### statistics.feature_usage.total
- Overall feature usage counts across all roles

### statistics.usage_percentage
- Percentage of users in each role using each feature
- Calculated as: (feature_users / total_role_users) * 100
- Rounded to 2 decimal places

### metadata
- `features_list`: List of all supported features
- `generated_at`: ISO 8601 timestamp when statistics were generated
- `total_analyzed_users`: Number of users included in the analysis

## Supported Features

The API tracks usage for these AI English features:

1. **essay** - English essay writing
2. **comprehension** - Reading comprehension 
3. **speaking_essay** - Oral essay composition
4. **speaking_conversation** - Speaking conversation practice
5. **sentence_builder** - Sentence construction exercises
6. **speaking_pronunciation** - Pronunciation practice

## Data Sources

The API analyzes users based on:
- `meta.aienglish_role`: User role ('teacher', 'student', or 'unknown')
- `meta.aienglish_features_list`: Array of enabled features for each user

## Performance Considerations

- Only queries users with non-null meta data for efficiency
- Uses `find_each` for memory-efficient batch processing
- Selects only required fields (id, meta, created_at)
- Handles JSON parsing gracefully with fallbacks

## Usage Examples

### cURL Example
```bash
curl -X GET \
  'https://your-api-domain.com/api/admin/v1/general_users/aienglish/statistics' \
  -H 'Authorization: Bearer YOUR_ADMIN_TOKEN' \
  -H 'Content-Type: application/json'
```

### JavaScript/Fetch Example
```javascript
const response = await fetch('/api/admin/v1/general_users/aienglish/statistics', {
  method: 'GET',
  headers: {
    'Authorization': 'Bearer YOUR_ADMIN_TOKEN',
    'Content-Type': 'application/json'
  }
});

const data = await response.json();
console.log('Role Distribution:', data.statistics.role_distribution);
console.log('Feature Usage:', data.statistics.feature_usage.total);
```

### Rails Console Testing
```ruby
# Test the API directly in Rails console
controller = Api::Admin::V1::GeneralUsersController.new
controller.aienglish_statistics

# Or query the data directly
users = GeneralUser.where.not(meta: nil)
teachers = users.select { |u| u.meta&.dig('aienglish_role') == 'teacher' }
students = users.select { |u| u.meta&.dig('aienglish_role') == 'student' }
```

## Error Handling

The API includes comprehensive error handling for:
- JSON parsing errors in feature lists
- Missing or malformed meta data
- Database query failures
- Calculation errors (division by zero)

All errors are logged and return a structured error response with details for debugging.

## Rate Limiting

Consider implementing rate limiting for this endpoint as it performs analytics calculations across all users.

## Caching Recommendations

For production use, consider:
- Caching results for 15-30 minutes
- Using Redis or Rails cache
- Invalidating cache when user data changes

```ruby
# Example caching implementation
def aienglish_statistics
  Rails.cache.fetch('aienglish_statistics', expires_in: 30.minutes) do
    # ... existing statistics logic
  end
end
```

## Security Considerations

- Endpoint requires admin authentication
- No sensitive user data is exposed
- Only aggregated statistics are returned
- No individual user identification possible from response