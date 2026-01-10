# frozen_string_literal: true

require "open3"

module SlackCli
  module Services
    class Encryption
      def available?
        system("which age > /dev/null 2>&1")
      end

      def encrypt(content, ssh_key_path, output_file)
        raise EncryptionError, "age encryption tool not available" unless available?

        public_key = "#{ssh_key_path}.pub"
        raise EncryptionError, "Public key not found: #{public_key}" unless File.exist?(public_key)

        _output, error, status = Open3.capture3("age", "-R", public_key, "-o", output_file, stdin_data: content)

        unless status.success?
          raise EncryptionError, "Failed to encrypt: #{error.strip}"
        end

        true
      end

      def decrypt(encrypted_file, ssh_key_path)
        return nil unless available?
        return nil unless File.exist?(encrypted_file)
        raise EncryptionError, "SSH key not found: #{ssh_key_path}" unless File.exist?(ssh_key_path)

        output, error, status = Open3.capture3("age", "-d", "-i", ssh_key_path, encrypted_file)

        unless status.success?
          raise EncryptionError, "Failed to decrypt #{encrypted_file}: #{error.strip}"
        end

        output
      rescue Errno::ENOENT => e
        raise EncryptionError, "Decryption failed: #{e.message}"
      end
    end
  end
end
