class QueueController < ApplicationController
  def index
    services = Engines::NagiosEngine.services.map(&:to_h)
    @queue = services.select { |s| s[:next_check].present? }.sort_by { |s| s[:next_check] }
  end
end
