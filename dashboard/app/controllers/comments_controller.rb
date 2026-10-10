class CommentsController < ApplicationController
  def index
    @comments = Engines::NagiosEngine.comments
    @hosts = Engines::NagiosEngine.hosts.map(&:to_h)
    @services = Engines::NagiosEngine.services.map(&:to_h)
  end

  def create
    host_name = params[:host_name]
    service_desc = params[:service_desc]
    comment_text = params[:comment]
    author = params[:author].presence || "nagiosadmin"

    if host_name.present? && comment_text.present?
      if service_desc.present?
        Engines::NagiosEngine.add_service_comment(host_name, service_desc, author, comment_text)
        redirect_back fallback_location: comments_path, notice: "Catatan insiden untuk #{service_desc} di #{host_name} berhasil ditambahkan!"
      else
        Engines::NagiosEngine.add_host_comment(host_name, author, comment_text)
        redirect_back fallback_location: comments_path, notice: "Catatan insiden untuk host #{host_name} berhasil ditambahkan!"
      end
    else
      redirect_back fallback_location: comments_path, alert: "Mohon isi nama host dan komentar."
    end
  end

  def destroy
    comment_id = params[:id]
    Engines::NagiosEngine.delete_comment(comment_id)
    redirect_to comments_path, notice: "Komentar ##{comment_id} berhasil dihapus."
  end
end
