# frozen_string_literal: true

# What a service returns when it can fail in a way its caller expects:
# the values the caller needs, and `error` — nil when it went
# through, else a symbol the caller words (`t("uploads.errors.#{error}")`).
# A service that can't fail that way returns its subject instead, and a
# broken invariant raises.
#
#   Result = ServiceResult.define(:upload)
#   result = Result.new(upload: upload, error: :quota)
#   result.failure?   # => true
module ServiceResult
  def self.define(*fields)
    Data.define(*fields, :error) do
      def success? = error.nil?
      def failure? = !success?
    end
  end
end
