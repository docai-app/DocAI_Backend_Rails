# frozen_string_literal: true

# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
# 压力测试和生产环境建议设置为更高的值
# 规则：pool (database.yml) >= RAILS_MAX_THREADS
# 
# 针对 Standard_B1ms (1 vCore, 2 GiB RAM) 的优化配置
# - Workers: 2 (通过 WEB_CONCURRENCY 环境变量设置)
# - Threads per worker: 25 (通过 RAILS_MAX_THREADS 环境变量设置)
# - 总并发 = 2 × 25 = 50（可以处理峰值 100，因为有请求排队）
# - 数据库连接池 = 30 (每个 worker 独立连接池)
# - PostgreSQL 总连接数 = 2 × 30 = 60 (在默认 100 限制内，安全)
# 注意：pool (database.yml) 应该 >= RAILS_MAX_THREADS
max_threads_count = ENV.fetch('RAILS_MAX_THREADS', 20)
min_threads_count = ENV.fetch('RAILS_MIN_THREADS') { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies the `worker_timeout` threshold that Puma will use to wait before
# terminating a worker in development environments.
#
worker_timeout 3600

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
port ENV['PORT'] || 3000

# Specifies the `environment` that Puma will run in.
#
environment ENV.fetch('RAILS_ENV', 'development')

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch('PIDFILE', 'tmp/pids/server.pid')

# Specifies the number of `workers` to boot in clustered mode.
# Workers are forked web server processes. If using threads and workers together
# the concurrency of the application would be max `threads` * `workers`.
# Workers do not work on JRuby or Windows (both of which do not support
# processes).
#
# 对于 100 个并发：建议使用 2 个 workers
# 设置方式：export WEB_CONCURRENCY=2
# 默认值：2（如果未设置环境变量，默认启用 2 个 workers）
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
#
# 只有当 workers > 0 时才启用 preload_app!
# 使用与 workers 相同的默认值逻辑，确保一致性
preload_app! if ENV.fetch("WEB_CONCURRENCY") { 2 }.to_i > 0

# Worker 启动和关闭钩子
# 确保每个 worker 有独立的数据库连接
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart