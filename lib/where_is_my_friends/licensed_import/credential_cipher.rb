# frozen_string_literal: true

require "base64"

module WhereIsMyFriends
  module LicensedImport
    class CredentialCipher
      MASTER_KEY_ENV = "WHERE_IS_MY_FRIENDS_CREDENTIALS_MASTER_KEY"
      VERSION = "v1"

      class << self
        def configured?
          master_key
          true
        rescue AiGateway::MissingCredentialMasterKey
          false
        end

        def encrypt(plaintext)
          "#{VERSION}:#{encryptor.encrypt_and_sign(plaintext.to_s)}"
        end

        def decrypt(ciphertext)
          version, payload = ciphertext.to_s.split(":", 2)
          raise AiGateway::InvalidCredential unless version == VERSION
          raise AiGateway::InvalidCredential if payload.blank?

          encryptor.decrypt_and_verify(payload)
        rescue ActiveSupport::MessageEncryptor::InvalidMessage
          raise AiGateway::InvalidCredential
        end

        private

        def encryptor
          ActiveSupport::MessageEncryptor.new(master_key, cipher: "aes-256-gcm")
        end

        def master_key
          encoded = ENV.fetch(MASTER_KEY_ENV)
          key = Base64.strict_decode64(encoded)
          raise AiGateway::MissingCredentialMasterKey unless key.bytesize == 32

          key
        rescue KeyError, ArgumentError
          raise AiGateway::MissingCredentialMasterKey
        end
      end
    end
  end
end
