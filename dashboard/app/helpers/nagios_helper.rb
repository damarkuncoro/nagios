module NagiosHelper
  def render_perf_data_widget(service)
    desc = service[:description].to_s.downcase
    output = service[:plugin_output].to_s

    if desc.include?("partition") || desc.include?("disk") || desc.include?("space")
      if output =~ /(\d+(?:\.\d+)?)\%/
        free_pct = $1.to_f
        used_pct = (100.0 - free_pct).round(1)
        bar_color = used_pct > 85 ? 'bg-red-500' : (used_pct > 70 ? 'bg-amber-500' : 'bg-indigo-500')

        return content_tag(:div, class: 'w-48 space-y-1 mt-1') do
          concat content_tag(:div, "#{used_pct}% Digunakan", class: 'text-xs text-slate-500 font-medium')
          concat(content_tag(:div, class: 'w-full bg-slate-100 rounded-full h-2 overflow-hidden border border-slate-200') do
            content_tag(:div, '', class: "h-full #{bar_color} transition-all duration-500", style: "width: #{used_pct}%")
          end)
        end
      end

    elsif desc.include?("load")
      if output =~ /load average:\s*([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)/i
        l1, l5, l15 = $1, $2, $3
        return content_tag(:div, class: 'flex gap-1.5 mt-1') do
          concat content_tag(:span, "1m: #{l1}", class: 'px-2 py-0.5 rounded bg-slate-100 text-slate-700 text-xs font-mono font-semibold')
          concat content_tag(:span, "5m: #{l5}", class: 'px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-xs font-mono')
          concat content_tag(:span, "15m: #{l15}", class: 'px-2 py-0.5 rounded bg-slate-100 text-slate-500 text-xs font-mono')
        end
      end

    elsif desc.include?("ping")
      if output =~ /RTA\s*=\s*([\d\.]+)\s*ms/i
        rta = $1.to_f
        badge_color = rta < 50 ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-amber-50 text-amber-700 border-amber-200'
        return content_tag(:div, class: 'mt-1') do
          content_tag(:span, "RTA: #{rta} ms", class: "px-2 py-0.5 rounded border text-xs font-mono font-semibold #{badge_color}")
        end
      end
    end

    nil
  end
end
