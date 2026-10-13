# frozen_string_literal: true

class DiscoveryController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:scan, :import]

  def index
    @cidr = params[:cidr] || '192.168.140.0/24'
    @community = params[:community] || 'public'
    @monitored_ips = fetch_monitored_ips
    @devices = []
  end

  def scan
    @cidr = params[:cidr].presence || '192.168.140.0/24'
    @community = params[:community].presence || 'public'
    @timeout = (params[:timeout].presence || 0.4).to_f
    @monitored_ips = fetch_monitored_ips

    t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @devices = Discovery::Services::NetworkScanner.scan_cidr(
      @cidr,
      community: @community,
      timeout: @timeout,
      concurrency: 24
    )
    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @duration = (t_end - t_start).round(2)

    render :index
  rescue StandardError => e
    flash.now[:alert] = "Scan error: #{e.message}"
    @devices = []
    render :index
  end

  def import
    res = Discovery::Services::DeviceImporter.import(
      ip: params[:ip],
      hostname: params[:hostname],
      vendor: params[:vendor],
      device_type: params[:device_type],
      snmp_descr: params[:snmp_descr],
      open_ports: params[:open_ports]
    )

    if res[:success]
      flash[:notice] = "Host '#{res[:host_name]}' successfully added to Nagios monitoring and config reloaded!"
    else
      flash[:alert] = "Failed to import host: #{res[:error]}"
    end

    redirect_to discovery_path(cidr: params[:cidr])
  end

  def interfaces
    @ip = params[:ip]
    @community = params[:community].presence || 'public'
    @interfaces = Discovery::Services::SnmpInterfaceWalker.walk(@ip, community: @community)
    render json: { ip: @ip, count: @interfaces.size, interfaces: @interfaces.map(&:to_h) }
  end

  private

  def fetch_monitored_ips
    cfg_path = Rails.root.join('config/nagios_sample.cfg')
    return [] unless File.exist?(cfg_path)

    catalog = Statuses::Services::ObjectConfigParser.parse(File.read(cfg_path)) rescue nil
    return [] unless catalog

    catalog.hosts.values.map { |h| h['address'] || h[:address] }.compact.uniq
  rescue StandardError
    []
  end
end
