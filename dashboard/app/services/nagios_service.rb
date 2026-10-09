class NagiosService
  def self.fetch_program_status
    Engines::NagiosEngine.program_status
  end

  def self.fetch_hosts
    Engines::NagiosEngine.hosts.map(&:to_h)
  end

  def self.fetch_services
    Engines::NagiosEngine.services.map(&:to_h)
  end

  def self.schedule_recheck(host_name)
    Statuses::UseCases::ScheduleCheck.host(host_name)
  end

  def self.schedule_service_recheck(host_name, service_desc)
    Statuses::UseCases::ScheduleCheck.service(host_name, service_desc)
  end

  def self.acknowledge_service_problem(host_name, service_desc, author, comment)
    Statuses::UseCases::AcknowledgeProblem.service(host_name, service_desc, author: author, comment: comment)
  end
end
