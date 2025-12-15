# frozen_string_literal: true

module SlackCli
  module Services
    class Encryption
      def available?
        system("which age > /dev/null 2>&1")
      end

      def encrypt(content, ssh_key_path, output_file)
        return false unless available?

        public_key = "#{ssh_key_path}.pub"
        return false unless File.exist?(public_key)

        IO.popen(["age", "-R", public_key, "-o", output_file], "w") do |io|
          io.write(content)
        end

        $?.success?
      end

      def decrypt(encrypted_file, ssh_key_path)
        return nil unless available?
        return nil unless File.exist?(encrypted_file)

        output, status = Open3.capture2("age", "-d", "-i", ssh_key_path, encrypted_file)
        status.success? ? output : nil
      rescue Errno::ENOENT
        nil
      end
    end
  end
end

require "open3"
