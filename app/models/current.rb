# frozen_string_literal: true

# Per-request (and per-job) memos, reset by Rails between them.
#   assistant_setting  the Assistant::Setting row (or :none), read once
#   platform_setting   the Platform::Setting row (or :none), read once
#   llm_context        the RubyLLM context built from it (Assistant.llm_context)
#   link_permissions   Links::Permissions per profile id
class Current < ActiveSupport::CurrentAttributes
  attribute :assistant_setting, :platform_setting, :llm_context, :link_permissions
end
