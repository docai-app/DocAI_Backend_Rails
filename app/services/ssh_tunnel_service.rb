# app/services/ssh_tunnel.rb
require 'net/ssh/gateway'

class SshTunnelService
  def self.open(domain, ssh_user, password, remote_port = 5432)
    gateway = Net::SSH::Gateway.new(domain, ssh_user, password:)

    # 开启隧道并返回本地端口，使用 nil 让系统自动选择端口
    local_port = gateway.open('localhost', remote_port, nil)

    puts "SSH tunnel established from local port #{local_port} to remote port #{remote_port}"

    # 返回 gateway 对象和本地端口，以便后续处理
    [gateway, local_port]
  rescue StandardError => e
    puts "Failed to open SSH tunnel: #{e.message}"
    nil
  end

  def self.close(gateway)
    gateway.shutdown! if gateway
    puts 'SSH tunnel closed'
  rescue StandardError => e
    puts "Failed to close SSH tunnel: #{e.message}"
  end
end
