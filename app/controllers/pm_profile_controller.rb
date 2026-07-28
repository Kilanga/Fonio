# Single-PM profile — one row in the `pms` table, created once and edited
# thereafter. No re-confirmation needed on each visit (unlike Technician),
# since the PM operates the app directly.
class PmProfileController < ApplicationController
  before_action :redirect_if_exists, only: [:new, :create]
  before_action :redirect_if_missing, only: [:edit, :update]

  def new
    @pm = Pm.new
  end

  def create
    @pm = Pm.new(pm_params)
    if @pm.save
      redirect_to root_path, notice: "Your profile is set up."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @pm = Pm.first
  end

  def update
    @pm = Pm.first
    if @pm.update(pm_params)
      redirect_to root_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def pm_params
    params.require(:pm).permit(:name, :phone, :region, :locale)
  end

  def redirect_if_exists
    redirect_to edit_pm_profile_path if Pm.exists?
  end

  def redirect_if_missing
    redirect_to new_pm_profile_path unless Pm.exists?
  end
end
