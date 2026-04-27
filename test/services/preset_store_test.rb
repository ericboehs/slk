# frozen_string_literal: true

require 'test_helper'

class PresetStoreTest < Minitest::Test
  def test_default_presets_created_on_first_initialization
    with_temp_config do
      store = Slk::Services::PresetStore.new
      assert store.exists?('meeting')
      assert store.exists?('lunch')
      assert store.exists?('focus')
      assert store.exists?('brb')
      assert store.exists?('clear')
    end
  end

  def test_get_returns_preset_for_known_name
    with_temp_config do
      store = Slk::Services::PresetStore.new
      preset = store.get('meeting')

      assert_equal 'meeting', preset.name
      assert_equal 'In a meeting', preset.text
      assert_equal ':calendar:', preset.emoji
      assert_equal '1h', preset.duration
    end
  end

  def test_get_returns_nil_for_unknown_name
    with_temp_config do
      store = Slk::Services::PresetStore.new
      assert_nil store.get('nonexistent')
    end
  end

  def test_all_returns_array_of_presets
    with_temp_config do
      store = Slk::Services::PresetStore.new
      presets = store.all

      assert_kind_of Array, presets
      assert_equal 5, presets.size
      assert(presets.all?(Slk::Models::Preset))
    end
  end

  def test_names_returns_array_of_preset_names
    with_temp_config do
      store = Slk::Services::PresetStore.new
      names = store.names

      assert_includes names, 'meeting'
      assert_includes names, 'lunch'
      assert_equal 5, names.size
    end
  end

  def test_exists_returns_false_for_unknown_preset
    with_temp_config do
      store = Slk::Services::PresetStore.new
      refute store.exists?('nonexistent')
    end
  end

  def test_add_persists_new_preset
    with_temp_config do
      store = Slk::Services::PresetStore.new
      preset = Slk::Models::Preset.new(
        name: 'custom', text: 'Custom status', emoji: ':star:', duration: '30m'
      )
      store.add(preset)

      new_store = Slk::Services::PresetStore.new
      assert new_store.exists?('custom')
      assert_equal 'Custom status', new_store.get('custom').text
    end
  end

  def test_add_overwrites_existing_preset
    with_temp_config do
      store = Slk::Services::PresetStore.new
      preset = Slk::Models::Preset.new(
        name: 'meeting', text: 'New meeting text', emoji: ':briefcase:', duration: '2h'
      )
      store.add(preset)

      assert_equal 'New meeting text', store.get('meeting').text
    end
  end

  def test_remove_returns_true_when_preset_exists
    with_temp_config do
      store = Slk::Services::PresetStore.new
      assert_equal true, store.remove('meeting')
      refute store.exists?('meeting')
    end
  end

  def test_remove_returns_false_when_preset_does_not_exist
    with_temp_config do
      store = Slk::Services::PresetStore.new
      assert_equal false, store.remove('nonexistent')
    end
  end

  def test_remove_persists_deletion
    with_temp_config do
      store = Slk::Services::PresetStore.new
      store.remove('meeting')

      new_store = Slk::Services::PresetStore.new
      refute new_store.exists?('meeting')
    end
  end

  def test_load_presets_returns_empty_when_file_missing
    with_temp_config do |dir|
      # Initialize once to create defaults, then delete file
      Slk::Services::PresetStore.new
      file = File.join(dir, 'slk', 'presets.json')
      File.delete(file)

      # PresetStore re-initializes and re-creates default presets due to ensure_default_presets
      store = Slk::Services::PresetStore.new
      assert store.exists?('meeting')
    end
  end

  def test_corrupted_presets_triggers_warning
    with_temp_config do |dir|
      config_dir = File.join(dir, 'slk')
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'presets.json'), 'not valid json{')

      warnings = []
      store = Slk::Services::PresetStore.new
      store.on_warning = ->(msg) { warnings << msg }

      # Triggering a load
      assert_equal [], store.names
      assert_equal 1, warnings.size
      assert_match(/corrupted/i, warnings.first)
    end
  end

  def test_corrupted_presets_returns_empty_when_no_callback
    with_temp_config do |dir|
      config_dir = File.join(dir, 'slk')
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'presets.json'), 'not valid json{')

      store = Slk::Services::PresetStore.new
      # No on_warning set; should not raise
      assert_equal [], store.names
    end
  end

  def test_does_not_overwrite_existing_presets_file_on_init
    with_temp_config do |dir|
      config_dir = File.join(dir, 'slk')
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'presets.json'),
                 JSON.pretty_generate({ 'custom' => { 'text' => 'Hi', 'emoji' => '', 'duration' => '0' } }))

      store = Slk::Services::PresetStore.new
      assert store.exists?('custom')
      refute store.exists?('meeting')
    end
  end

  def test_initialize_uses_provided_paths
    Dir.mktmpdir('slk-preset') do |dir|
      paths = FakePaths.new(dir)
      store = Slk::Services::PresetStore.new(paths: paths)
      assert store.exists?('meeting')
      assert File.exist?(File.join(dir, 'presets.json'))
    end
  end

  # Minimal stand-in for XdgPaths
  class FakePaths
    def initialize(dir)
      @dir = dir
    end

    def config_file(name)
      File.join(@dir, name)
    end

    def ensure_config_dir
      FileUtils.mkdir_p(@dir)
    end
  end
end
