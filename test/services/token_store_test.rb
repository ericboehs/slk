# frozen_string_literal: true

require 'test_helper'

class TokenStoreTest < Minitest::Test
  def test_empty_returns_true_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert store.empty?
    end
  end

  def test_empty_returns_false_when_tokens_exist
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      refute store.empty?
    end
  end

  def test_workspace_names_returns_empty_array_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert_equal [], store.workspace_names
    end
  end

  def test_workspace_names_returns_all_names
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'workspace1' => { 'token' => 'xoxb-test1' },
                          'workspace2' => { 'token' => 'xoxb-test2' }
                        })
      store = Slk::Services::TokenStore.new
      assert_equal %w[workspace1 workspace2].sort, store.workspace_names.sort
    end
  end

  def test_exists_returns_false_for_unknown_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      refute store.exists?('nonexistent')
    end
  end

  def test_exists_returns_true_for_known_workspace
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      assert store.exists?('myworkspace')
    end
  end

  def test_workspace_raises_for_unknown_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      error = assert_raises(Slk::WorkspaceNotFoundError) do
        store.workspace('nonexistent')
      end
      assert_equal "Workspace 'nonexistent' not found", error.message
    end
  end

  def test_workspace_returns_workspace_model
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test-token' } })
      store = Slk::Services::TokenStore.new
      workspace = store.workspace('myworkspace')

      assert_kind_of Slk::Models::Workspace, workspace
      assert_equal 'myworkspace', workspace.name
      assert_equal 'xoxb-test-token', workspace.token
    end
  end

  def test_workspace_returns_workspace_with_cookie
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'myworkspace' => { 'token' => 'xoxc-test-token', 'cookie' => 'xoxd-cookie' }
                        })
      store = Slk::Services::TokenStore.new
      workspace = store.workspace('myworkspace')

      assert_equal 'xoxc-test-token', workspace.token
      assert_equal 'xoxd-cookie', workspace.cookie
    end
  end

  def test_all_workspaces_returns_empty_array_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert_equal [], store.all_workspaces
    end
  end

  def test_all_workspaces_returns_workspace_models
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'ws1' => { 'token' => 'xoxb-test1' },
                          'ws2' => { 'token' => 'xoxb-test2' }
                        })
      store = Slk::Services::TokenStore.new
      workspaces = store.all_workspaces

      assert_equal 2, workspaces.size
      assert(workspaces.all? { |ws| ws.is_a?(Slk::Models::Workspace) })
      assert_equal %w[ws1 ws2].sort, workspaces.map(&:name).sort
    end
  end

  def test_add_creates_new_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxb-new-token')

      assert store.exists?('newworkspace')
      workspace = store.workspace('newworkspace')
      assert_equal 'xoxb-new-token', workspace.token
    end
  end

  def test_add_with_cookie_stores_cookie
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxc-new-token', 'xoxd-cookie')

      workspace = store.workspace('newworkspace')
      assert_equal 'xoxc-new-token', workspace.token
      assert_equal 'xoxd-cookie', workspace.cookie
    end
  end

  def test_add_persists_to_file
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxb-new-token')

      # Create new store instance and verify data persisted
      new_store = Slk::Services::TokenStore.new
      assert new_store.exists?('newworkspace')
    end
  end

  def test_remove_returns_true_when_workspace_existed
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new

      result = store.remove('myworkspace')

      assert result
      refute store.exists?('myworkspace')
    end
  end

  def test_remove_returns_false_when_workspace_not_found
    with_temp_config do
      store = Slk::Services::TokenStore.new
      result = store.remove('nonexistent')
      refute result
    end
  end

  def test_remove_persists_change
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      store.remove('myworkspace')

      # Create new store instance and verify removal persisted
      new_store = Slk::Services::TokenStore.new
      refute new_store.exists?('myworkspace')
    end
  end

  # Corruption handling tests
  def test_corrupted_tokens_file_raises_error
    with_temp_config do |dir|
      config_dir = "#{dir}/slk"
      FileUtils.mkdir_p(config_dir)
      File.write("#{config_dir}/tokens.json", 'not valid json{')

      store = Slk::Services::TokenStore.new

      error = assert_raises(Slk::TokenStoreError) do
        store.empty?
      end

      assert_match(/corrupted/, error.message)
    end
  end

  def test_on_warning_callback_is_settable
    store = Slk::Services::TokenStore.new
    callback = ->(msg) { puts msg }
    store.on_warning = callback
    assert_equal callback, store.on_warning
  end

  # File permissions test
  def test_add_creates_file_with_restricted_permissions
    with_temp_config do |dir|
      store = Slk::Services::TokenStore.new
      store.add('testws', 'xoxb-test')

      config_dir = "#{dir}/slk"
      tokens_file = "#{config_dir}/tokens.json"

      assert File.exist?(tokens_file)
      # Check file mode (0600 = owner read/write only)
      mode = File.stat(tokens_file).mode & 0o777
      assert_equal 0o600, mode
    end
  end

  # Validation tests
  def test_add_validates_token_format
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('testws', 'invalid-token')
      end

      assert_match(/invalid token format/, error.message)
    end
  end

  def test_add_validates_name_not_empty
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('', 'xoxb-test')
      end

      assert_match(/name cannot be empty/, error.message)
    end
  end

  def test_add_validates_xoxc_requires_cookie
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('testws', 'xoxc-test')
      end

      assert_match(/require a cookie/, error.message)
    end
  end

  private

  def write_tokens_file(dir, tokens)
    config_dir = "#{dir}/slk"
    FileUtils.mkdir_p(config_dir)
    File.write("#{config_dir}/tokens.json", JSON.generate(tokens))
  end
end
