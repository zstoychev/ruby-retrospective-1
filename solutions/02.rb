class Song
  attr_reader :name, :artist, :genre, :subgenre, :tags
  
  def initialize(name, artist, genre, subgenre, tags)
    @name, @artist, @tags = name, artist, tags
    @genre, @subgenre = genre, subgenre
  end
  
  def matches?(criteria)
    criteria.all? do |type, value|
      case type
        when :name then name == value
        when :artist then artist == value
        when :filter then value.(self)
        when :tags then matches_tags? [*value]
      end
    end
  end
  
  def matches_tag?(tag)
    tag.end_with?("!") ^ tags.include?(tag.chomp "!")
  end
  
  def matches_tags?(tags)
    tags.all? { |tag| matches_tag? tag }
  end
end

class Collection
  def initialize(songs_string, artist_tags)
    @songs = songs_string.lines.map { |song| song.split(".").map(&:strip) }
    @songs = @songs.map do |name, artist, genres_string, tags_string|
      genre, subgenre = genres_string.split(",").map(&:strip)
      tags = artist_tags.fetch(artist, [])
      tags += [genre, subgenre].compact.map(&:downcase)
      tags += tags_string.split(",").map(&:strip) unless tags_string.nil?
      
      Song.new(name, artist, genre, subgenre, tags)
    end
  end
  
  def find(criteria)
    @songs.select { |song| song.matches?(criteria) }
  end
end
