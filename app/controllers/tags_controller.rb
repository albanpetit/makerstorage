# frozen_string_literal: true

class TagsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_tag, only: %i[update destroy]

  def index
    tags = current_organization.tags
      .left_joins(:parts)
      .select("tags.*, COUNT(parts.id) AS parts_count")
      .group("tags.id")
      .alphabetical

    render inertia: "tags/index", props: {
      tags: tags.map { |tag| serialize_tag(tag) }
    }
  end

  # Also used for inline creation from the part form so a fresh organization
  # (which starts with no tags) can define one without leaving the part flow.
  # `redirect_back_or_to` returns to whichever page posted.
  def create
    tag = current_organization.tags.build(tag_params)

    if tag.save
      redirect_back_or_to tags_path, notice: "Tag \"#{tag.name}\" created."
    else
      redirect_back_or_to tags_path, alert: "Failed to create tag.", inertia: { errors: tag.errors }
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "Tag updated successfully."
    else
      redirect_back_or_to tags_path, alert: "Failed to update tag.", inertia: { errors: @tag.errors }
    end
  end

  def destroy
    if @tag.destroy
      redirect_to tags_path, notice: "Tag deleted successfully."
    else
      redirect_to tags_path, alert: @tag.errors.full_messages.to_sentence
    end
  end

  private

  def set_tag
    @tag = current_organization.tags.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name, :color, :description)
  end

  def serialize_tag(tag)
    {
      id: tag.id,
      name: tag.name,
      color: tag.color,
      description: tag.description,
      parts_count: tag.attributes["parts_count"] || 0
    }
  end
end
