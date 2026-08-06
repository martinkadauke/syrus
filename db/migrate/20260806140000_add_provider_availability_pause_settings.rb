class AddProviderAvailabilityPauseSettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:users, :provider_availability_overrides)
      add_column :users, :provider_availability_overrides, :json
    end

    unless column_exists?(:users, :provider_availability_pause_thresholds)
      add_column :users, :provider_availability_pause_thresholds, :json
    end
  end
end
