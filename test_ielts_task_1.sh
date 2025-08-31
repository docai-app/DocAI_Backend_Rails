#!/bin/bash

# IELTS Task 1 測試腳本
echo "🎯 開始 IELTS Task 1 功能測試"
echo "=================================="

# 設定變數
API_BASE="http://localhost:3000/api/v1"
JWT_TOKEN="YOUR_JWT_TOKEN_HERE"  # 請替換為實際的 JWT token

echo "📝 第一步：創建 IELTS Task 1 作業"
echo "--------------------------------"

# 創建 IELTS Task 1 作業的 CURL 命令
cat << 'EOF'
curl -X POST "${API_BASE}/essay_assignments" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "essay_assignment[topic]=The chart shows the percentage of transportation modes used in City A from 1990 to 2020" \
  -F "essay_assignment[assignment]=The chart below shows the percentage of people using different types of transportation in City A from 1990 to 2020. Summarise the information by selecting and reporting the main features, and make comparisons where relevant. Write at least 150 words." \
  -F "essay_assignment[title]=IELTS Task 1 - Transportation Chart Analysis" \
  -F "essay_assignment[category]=essay" \
  -F "essay_assignment[graph_image]=@/path/to/your/chart.jpg" \
  -F "essay_assignment[rubric][name]=IELTS Task 1" \
  -F "essay_assignment[rubric][app_key][grading]=YOUR_IELTS_GRADING_API_KEY" \
  -F "essay_assignment[rubric][app_key][general_context]=YOUR_GENERAL_CONTEXT_API_KEY"
EOF

echo ""
echo "📊 第二步：學生提交作文"
echo "----------------------"

cat << 'EOF'
curl -X POST "${API_BASE}/essay_assignments/{ASSIGNMENT_ID}/essay_gradings" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "essay_grading": {
      "essay": "The chart illustrates the changes in transportation preferences among residents of City A over a 30-year period from 1990 to 2020. Overall, there was a significant shift from private car usage towards more sustainable transportation methods. In 1990, private cars dominated with 60% usage, followed by public transport at 25%, cycling at 10%, and walking at 5%. By 2020, the landscape had changed dramatically. Public transport usage increased substantially to 40%, while private car usage dropped to 35%. Cycling saw the most remarkable growth, rising from 10% to 20%. Walking also increased modestly to 5%. This trend suggests a growing environmental awareness and improved public transportation infrastructure in City A over this period.",
      "topic": "Transportation modes analysis in City A"
    }
  }'
EOF

echo ""
echo "🔍 第三步：檢查日誌驗證功能"
echo "---------------------------"
echo "檢查以下日誌訊息來確認 IELTS Task 1 邏輯是否正常運作："
echo ""
echo "✅ 預期看到的日誌："
echo "[EssayGradingService] Building IELTS Task 1 inputs for assignment [ID]"
echo "[EssayGradingService] Graph URL: https://..."
echo "[EssayGradingService] Essay length: [數字]"
echo "[EssayGradingService] Topic: Transportation modes analysis in City A"
echo ""
echo "❌ 如果是舊格式，會看到："
echo "[EssayGradingService] Including graph image URL for grading assignment [ID]"
echo ""
echo "📋 監控命令："
echo "tail -f log/development.log | grep -i 'IELTS\\|EssayGradingService'" 