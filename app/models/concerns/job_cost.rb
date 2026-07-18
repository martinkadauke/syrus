module JobCost
  extend ActiveSupport::Concern

  def total_cost_usd
    if runs.loaded?
      runs.sum { |run| run.cost_usd.to_d }
    else
      runs.sum(:cost_usd)
    end
  end

  def display_total_cost_usd
    return nil if billed_runs_count.zero?

    total_cost_usd
  end

  def billed_runs_count
    if runs.loaded?
      runs.count { |run| run.cost_usd.present? }
    else
      runs.where.not(cost_usd: nil).count
    end
  end
end
