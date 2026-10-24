# frozen_string_literal: true

# Network label printers (Settings → Label printers) and direct printing to
# them. The browser renders each label as a 1-bit bitmap at the printer's
# geometry; #print checks its size and hands it to LabelPrinter#print_bitmaps.
class LabelPrintersController < ApplicationController
  include Auth

  # Labels per request; the browser sends bigger batches in several requests.
  MAX_LABELS = 50

  before_action :verify_organization_access
  before_action :verify_organization_admin, only: %i[create update destroy]
  before_action :verify_organization_writer, only: :print
  before_action :set_printer, only: %i[update destroy print]

  rate_limit to: 30, within: 1.minute, only: :print, by: -> { current_user.id }, store: AUTH_RATE_LIMIT_STORE,
             with: -> { render json: { error: I18n.t("flash.label_printers.too_many_jobs") }, status: :too_many_requests }

  # The print dialogs fetch the organization's printers with their geometry.
  def index
    render json: {
      enabled: LabelPrinting::Network.enabled?,
      printers: current_organization.label_printers.alphabetical.map { |printer| serialize(printer) }
    }
  end

  def create
    printer = current_organization.label_printers.build(printer_params)

    if printer.save
      redirect_to settings_path(section: "printers"), notice: t("flash.label_printers.added", name: printer.name)
    else
      redirect_to settings_path(section: "printers"), alert: t("flash.label_printers.add_failed"),
                                                     inertia: { errors: inertia_errors(printer, as: :label_printer) }
    end
  end

  def update
    if @printer.update(printer_params)
      redirect_to settings_path(section: "printers"), notice: t("flash.label_printers.updated")
    else
      redirect_to settings_path(section: "printers"), alert: t("flash.label_printers.update_failed"),
                                                     inertia: { errors: inertia_errors(@printer, as: :label_printer) }
    end
  end

  def destroy
    @printer.destroy!
    redirect_to settings_path(section: "printers"), notice: t("flash.label_printers.removed", name: @printer.name)
  end

  # Body: { labels: [base64 bitmap, …] }, each a packed 1-bit image at the
  # printer's geometry (see LabelPrinter#geometry).
  def print
    labels = Array(params[:labels])
    return render(json: { error: t("flash.label_printers.nothing_to_print") }, status: :unprocessable_entity) if labels.empty?
    return render(json: { error: t("flash.label_printers.too_many_labels", count: MAX_LABELS) }, status: :unprocessable_entity) if labels.size > MAX_LABELS

    expected = @printer.bitmap_bytesize
    bitmaps = labels.map { |label| Base64.strict_decode64(label.to_s) }
    unless bitmaps.all? { |bitmap| bitmap.bytesize == expected }
      return render json: { error: t("flash.label_printers.size_mismatch") }, status: :unprocessable_entity
    end

    @printer.print_bitmaps(bitmaps)
    render json: { printed: bitmaps.size }
  rescue ArgumentError
    render json: { error: t("flash.label_printers.unreadable") }, status: :unprocessable_entity
  rescue LabelPrinting::Network::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def set_printer
    @printer = current_organization.label_printers.find(params[:id])
  end

  def printer_params
    params.require(:label_printer).permit(:name, :protocol, :host, :port, :media, :width_mm, :length_mm, :dpi)
  end

  def serialize(printer)
    { id: printer.id, name: printer.name, size: printer.size_label, **printer.geometry }
  end
end
