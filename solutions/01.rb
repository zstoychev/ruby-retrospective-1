class Array
  def to_hash
    {}.tap do |result|    
      each { |key, value| result[key] = value}
    end
  end
  
  def index_by(&block)
    map(&block).zip(self).to_hash
  end
  
  def subarray_count(subarray)
    each_cons(subarray.length).count subarray
  end
  
  def occurences_count
    Hash.new(0).tap do |result|
      each { |element| result[element] += 1 }
    end
  end
end
