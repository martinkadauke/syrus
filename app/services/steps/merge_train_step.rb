module Steps
  # Shared helpers for the Epic merge-train steps. The MergeTrain row is
  # created by the dispatcher (LandingQueueProcessor) and referenced from
  # the Workflow's artifacts under "merge_train_id".
  module MergeTrainStep
    private

    def merge_train
      @merge_train ||= begin
        id = workflow.artifact("merge_train_id")
        raise Base::StepFailed, "merge_train: workflow has no merge_train_id artifact" if id.blank?

        MergeTrain.find_by(id: id) ||
          raise(Base::StepFailed, "merge_train: MergeTrain ##{id} not found")
      end
    end

    def epic
      merge_train.epic
    end
  end
end
