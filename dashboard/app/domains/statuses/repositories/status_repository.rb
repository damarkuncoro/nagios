module Statuses
  module Repositories
    class StatusRepository
      def fetch_program_status
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #fetch_program_status"
      end

      def fetch_hosts
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #fetch_hosts"
      end

      def fetch_services
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #fetch_services"
      end

      def schedule_host_recheck(host_name)
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #schedule_host_recheck"
      end

      def schedule_service_recheck(host_name, service_desc)
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #schedule_service_recheck"
      end

      def acknowledge_service_problem(host_name, service_desc, author, comment)
        raise NotImplementedError, "#{self.class} harus mengimplementasikan #acknowledge_service_problem"
      end
    end
  end
end
