require 'abstract_unit'

class DispatcherTest < Test::Unit::TestCase
  Dispatcher = ActionController::Dispatcher

  class Foo
    cattr_accessor :a, :b
  end

  def setup
    ENV['REQUEST_METHOD'] = 'GET'

    # Clear callbacks as they are redefined by Dispatcher#define_dispatcher_callbacks
    ActionDispatch::Callbacks.reset_callbacks(:prepare)
    ActionDispatch::Callbacks.reset_callbacks(:call)

    @old_router, Dispatcher.router = Dispatcher.router, mock()
    Dispatcher.router.stubs(:call).returns([200, {}, 'response'])
    Dispatcher.router.stubs(:reload)
    Dispatcher.stubs(:require_dependency)
  end

  def teardown
    Dispatcher.router = @old_router
    @dispatcher = nil
    ENV.delete 'REQUEST_METHOD'
  end

  def test_clears_dependencies_after_dispatch_if_in_loading_mode
    ActiveSupport::Dependencies.expects(:clear).once
    dispatch(false)
  end

  def test_reloads_routes_before_dispatch_if_in_loading_mode
    Dispatcher.router.expects(:reload).once
    dispatch(false)
  end

  def test_leaves_dependencies_after_dispatch_if_not_in_loading_mode
    Dispatcher.router.expects(:reload).never
    ActiveSupport::Dependencies.expects(:clear).never

    dispatch
  end

  # Stub out dispatch error logger
  class << Dispatcher
    def log_failsafe_exception(status, exception); end
  end

  def test_prepare_callbacks
    a = b = c = nil
    Dispatcher.to_prepare { |*args| a = b = c = 1 }
    Dispatcher.to_prepare { |*args| b = c = 2 }
    Dispatcher.to_prepare { |*args| c = 3 }

    # Ensure to_prepare callbacks are not run when defined
    assert_nil a || b || c

    # Run callbacks
    dispatch

    assert_equal 1, a
    assert_equal 2, b
    assert_equal 3, c

    # Make sure they are only run once
    a = b = c = nil
    dispatch
    assert_nil a || b || c
  end

  def test_to_prepare_with_identifier_replaces
    Dispatcher.to_prepare(:unique_id) { |*args| Foo.a, Foo.b = 1, 1 }
    Dispatcher.to_prepare(:unique_id) { |*args| Foo.a = 2 }

    dispatch
    assert_equal 2, Foo.a
    assert_equal nil, Foo.b
  end

  private
    def dispatch(cache_classes = true)
      ActionController::Dispatcher.prepare_each_request = false
      Dispatcher.define_dispatcher_callbacks(cache_classes)

      @dispatcher ||= Dispatcher.new
      @dispatcher.call({'rack.input' => StringIO.new(''), 'action_dispatch.show_exceptions' => false})
    end

    def assert_subclasses(howmany, klass, message = klass.subclasses.inspect)
      assert_equal howmany, klass.subclasses.size, message
    end
end
