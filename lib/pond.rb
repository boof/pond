require 'thread'

require 'pond/version'

class Pond
  class Timeout < StandardError; end

  attr_reader :allocated

  def initialize(options = {}, &block)
    @timeout  = options[:timeout]      || 1.0
    @max_size = options[:maximum_size] || 10

    @block = block
    @mutex = Mutex.new
    @cv    = ConditionVariable.new

    @available = []
    @allocated = {}
  end

  def checkout(&block)
    if object = @mutex.synchronize { @allocated[Thread.current] }
      yield object
    else
      _checkout(&block)
    end
  end

  def size
    @mutex.synchronize { _size }
  end

  private

  def _checkout
    object   = nil
    deadline = Time.now + @timeout

    loop do
      time_left = deadline - Time.now
      raise Timeout if time_left < 0

      @mutex.synchronize do
        if @available.empty?
          if _size >= @max_size
            @cv.wait(@mutex, time_left)
          else
            object = @block.call
          end
        else
          object = @available.shift
        end

        @allocated[Thread.current] = object if object
      end

      break if object
    end

    yield object
  ensure
    if object
      @mutex.synchronize do
        @allocated.delete(Thread.current)
        @available << object
        @cv.signal
      end
    end
  end

  def _size
    @available.size + @allocated.size
  end
end
