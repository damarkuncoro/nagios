module Statuses
  module Services
    class FreshnessDetector
      DEFAULT_TOLERANCE_SECONDS = 300 # 5 menit toleransi keterlambatan check

      class << self
        def fresh?(status_record, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS, current_time: Time.now)
          !stale?(status_record, tolerance_seconds: tolerance_seconds, current_time: current_time)
        end

        def stale?(status_record, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS, current_time: Time.now)
          return false if status_record.nil?

          # Jika checks dinonaktifkan, status tidak dianggap stale karena sengaja di-pause
          checks_enabled = status_record.respond_to?(:checks_enabled) ? status_record.checks_enabled : status_record[:checks_enabled]
          return false if checks_enabled == false

          next_check = status_record.respond_to?(:next_check) ? status_record.next_check : status_record[:next_check]
          last_check = status_record.respond_to?(:last_check) ? status_record.last_check : status_record[:last_check]

          # Kasus 1: Ada waktu next_check yang telah lewat melampaui batas toleransi
          if next_check.present? && next_check.is_a?(Time)
            return (current_time - next_check) > tolerance_seconds
          end

          # Kasus 2: Tidak ada next_check, periksa apakah last_check sudah terlalu lama (e.g. > 15 menit)
          if last_check.present? && last_check.is_a?(Time)
            return (current_time - last_check) > (tolerance_seconds * 3)
          end

          false
        end
      end
    end
  end
end
