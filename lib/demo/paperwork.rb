# frozen_string_literal: true

module Demo
  # The Files section. The household's paperwork comes in over the months:
  # Alex scans the lease and the insurance, Sam keeps the car's and the
  # boiler's papers and a few photos, Robin a school form. Some are shared
  # with another of them and downloaded now and then. The files are real,
  # small, and written through the same code an upload goes through; no
  # public links — the demo household can't make them.
  class Paperwork < Part
    # who, name, days after the start, shared with (nil for no one), content type
    FILES = [
      [ :alex, "Lease 2026-2027.pdf", 3, :sam, "application/pdf" ],
      [ :alex, "Home insurance policy.pdf", 9, nil, "application/pdf" ],
      [ :sam, "Car registration.pdf", 15, :alex, "application/pdf" ],
      [ :sam, "Boiler service report.txt", 31, nil, "text/plain" ],
      [ :alex, "Electricity contract.pdf", 52, nil, "application/pdf" ],
      [ :robin, "School trip consent form.pdf", 77, :alex, "application/pdf" ],
      [ :sam, "Kitchen tiles - quotes.csv", 98, :alex, "text/csv" ],
      [ :alex, "Vet records - Milo.txt", 123, :sam, "text/plain" ],
      [ :sam, "Balcony photos.txt", 150, nil, "text/plain" ],
      [ :alex, "Tax return 2025.pdf", 171, nil, "application/pdf" ]
    ].freeze

    private

    # Its own dice, seeded by the date like the seeder's: the other parts'
    # stories don't change because a few files came in.
    def setup
      @rng = Random.new(start.jd + 17)
      FILES.each do |who, name, after, with, content_type|
        day = start + after
        at(day) do
          upload = keep(send(who), name, content_type, day)
          share(upload, with: send(with)) if with
          downloads = with ? @rng.rand(1..3) : @rng.rand(0..1)
          downloads.times do |n|
            at(day + @rng.rand(1..20) + n) { download(upload, with ? send(with) : send(who)) }
          end
        end
      end
    end

    # A small file with words in it, uploaded whole in one chunk and finished
    # the way Uploads::FinishJob finishes one.
    def keep(owner, name, content_type, day)
      body = contents(name, day)
      result = Uploads::Create.call(owner: owner, name: name, byte_size: body.bytesize, content_type: content_type)
      upload = result.upload
      raise "demo file refused: #{result.error}" unless result.success?

      Uploads::Append.call(upload, io: StringIO.new(body), offset: 0, length: body.bytesize)
      Uploads::FinishJob.perform_now(upload.reload)
      upload.reload
    end

    def download(upload, by)
      return unless upload.ready?

      UploadActivity.record(upload, :downloaded, actor: by)
    end

    # Words, under a PDF header when the name says so: the type is read from
    # the first bytes, not from the name.
    def contents(name, day)
      lines = [ ("%PDF-1.4" if name.end_with?(".pdf")), name.to_s, "Demo household — #{day.strftime("%B %Y")}", "" ].compact
      lines += Array.new(@rng.rand(8..40)) { |i| "Line #{i + 1}: #{%w[lorem ipsum dolor sit amet consectetur adipiscing elit].shuffle(random: @rng).join(" ")}" }
      lines.join("\n") + "\n"
    end
  end
end
