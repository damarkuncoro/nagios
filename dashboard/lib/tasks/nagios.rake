# frozen_string_literal: true

namespace :nagios do
  desc "Tampilkan ringkasan status monitoring live di terminal (CLI Summary)"
  task status: :environment do
    puts "\n" + ("=" * 70)
    puts "  💎 NAGIOS CORE PURE-RUBY ENGINE - CLI STATUS OVERVIEW"
    puts ("=" * 70)

    prog = Engines::NagiosEngine.program_status
    if prog
      puts "  Version      : #{prog[:version]}"
      puts "  PID          : #{prog[:pid]}"
      puts "  Program Start: #{prog[:program_start]}"
      puts "  Notifications: #{prog[:notifications_enabled] ? 'ENABLED' : 'DISABLED'}"
      puts "  Checks       : #{prog[:service_checks_enabled] ? 'ENABLED' : 'DISABLED'}"
    else
      puts "  Status: Engine status tidak ditemukan (daemon belum aktif)."
    end

    hosts = Engines::NagiosEngine.hosts
    services = Engines::NagiosEngine.services

    puts "\n  📦 HOSTS (#{hosts.size}):"
    hosts.each do |h|
      color = h.up? ? "\e[32m" : "\e[31m"
      puts "    #{color}●\e[0m #{h.name.ljust(16)} [#{h.status.ljust(11)}] #{h.plugin_output}"
    end

    puts "\n  ⚙️  SERVICES (#{services.size}):"
    services.each do |s|
      color = case s.status
              when 'OK' then "\e[32m"
              when 'WARNING' then "\e[33m"
              when 'CRITICAL' then "\e[31m"
              else "\e[35m"
              end
      puts "    #{color}●\e[0m #{"#{s.host_name}/#{s.description}".ljust(32)} [#{s.status.ljust(8)}] #{s.plugin_output}"
    end

    puts "\n" + ("=" * 70) + "\n"
  end

  desc "Verifikasi sintaks file konfigurasi Nagios (.cfg)"
  task :verify, [:config_file] => :environment do |_t, args|
    file = args[:config_file].presence || Rails.root.join("config/nagios_sample.cfg").to_s
    unless File.exist?(file)
      puts "❌ File konfigurasi tidak ditemukan: #{file}"
      exit 1
    end

    puts "📦 Memverifikasi: #{file}"
    catalog = Statuses::Services::ObjectConfigParser.parse_file(file)
    puts "  ✓ Hosts terdaftar    : #{catalog.hosts.size}"
    puts "  ✓ Services terdaftar : #{catalog.services.size}"
    puts "  ✓ Commands terdaftar : #{catalog.commands.size}"
    puts "✅ Sintaks konfigurasi valid dan siap digunakan!\n"
  end

  desc "Kirim notifikasi pengujian webhook (Slack / Discord / Generic)"
  task :test_webhook, [:url] => :environment do |_t, args|
    target_url = args[:url].presence || ENV["SLACK_WEBHOOK_URL"]
    if target_url.blank?
      puts "❌ Masukkan URL webhook: bin/rails 'nagios:test_webhook[https://hooks.slack.com/...]' atau set SLACK_WEBHOOK_URL"
      exit 1
    end

    puts "📢 Mengirim pesan pengujian ke: #{target_url}..."
    res = Statuses::Services::NotificationService.deliver_alert(
      host_name: "production-gateway",
      service_desc: "Database Latency",
      status: "WARNING",
      plugin_output: "Test alert dispatched from Pure-Ruby Nagios Engine",
      target_url: target_url
    )

    if res.success?
      puts "✅ Notifikasi berhasil terkirim ke platform: #{res.platform}!"
    else
      puts "❌ Pengiriman gagal: #{res.error}"
    end
  end

  desc "Suntikkan passive check ke FIFO nagios.cmd"
  task :inject_check, [:host, :service, :code, :output] => :environment do |_t, args|
    host = args[:host] || "localhost"
    service = args[:service]
    code = (args[:code] || 0).to_i
    output = args[:output] || "Manual check injection via Rake"

    Engines::NagiosEngine.submit_passive_check(host, service, code, output)
    puts "✅ Passive check berhasil disuntikkan ke command pipe: [#{host}#{service ? "/#{service}" : ""}] Code=#{code}"
  end
end
