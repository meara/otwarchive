class TagSet < ActiveRecord::Base
  
  TAG_TYPES = %w(fandom character pairing freeform category rating warning)
  
  has_many :set_taggings, :dependent => :destroy
  has_many :tags, :through => :set_taggings

  has_one :prompt

  # how this works: we don't want to set the actual "tags" variable initially because that will
  # create SetTaggings even if the tags are not canonical or wrong. So we need to create a temporary
  # virtual attribute "tagnames" to use instead until after validation.
  attr_writer :tagnames
  def tagnames
    @tagnames || tags.collect(&:name).join(ArchiveConfig.DELIMITER_FOR_OUTPUT).sort
  end
  def taglist
    @tagnames ? tagnames_to_list(@tagnames) : tags
  end
  
  # this code just sets up functions fandom_tagnames/fandom_tagnames=, character_tagnames... etc
  # that work like tagnames above, except on separate types. 
  # 
  # NOTE: you can't use both these individual
  # setters and tagnames in the same form -- ie, if you set tagnames and then you set fandom_tagnames, you
  # will wipe out the fandom tagnames set in tagnames.
  #
  TAG_TYPES.each do |type|
    attr_writer "#{type}_tagnames".to_sym

    define_method("#{type}_tagnames") do
      eval("@#{type}_tagnames") || self.with_type(type.classify).collect(&:name).join(ArchiveConfig.DELIMITER_FOR_OUTPUT).sort
    end
    
    define_method("#{type}_taglist") do
      eval("@#{type}_tagnames") ? tagnames_to_list(eval("@#{type}_tagnames"), "#{type}") : with_type(type)
    end
  end

  # this actually runs and saves the tags but only after validation
  after_save :assign_tags
  def assign_tags
    if @tagnames
      self.tags = tagnames_to_list(@tagnames)
    end
    
    TAG_TYPES.each do |type|
      if eval("@#{type}_tagnames")
        new_tags = eval("#{type}_taglist")
        old_tags = self.with_type(type.classify)
        tags_to_set = (self.tags - old_tags + new_tags).compact.uniq
        self.tags = tags_to_set
      end
    end
  end

  validate :all_tags_must_be_canonical  
  def all_tags_must_be_canonical
    uncanonical_tags = self.taglist.reject {|tag| tag.canonical}
    unless uncanonical_tags.empty?
      errors.add(:tagnames, t('tag_set.must_be_canonical', 
                :default => "^The following tags aren't canonical and can't be used: {{taglist}}", 
                :taglist => uncanonical_tags.collect(&:name).join(", ") ))
    end
    
    TAG_TYPES.each do |type|
      uncanonical_tags = eval("#{type}_taglist").reject {|tag| tag.canonical}
      unless uncanonical_tags.empty?
        errors.add("#{type}_tagnames", t("tag_set.#{type}_must_be_canonical", 
                  :default => "^The following #{type} tags aren't canonical and can't be used: {{taglist}}", 
                  :taglist => uncanonical_tags.collect(&:name).join(", ") ))
      end
    end
  end
  
  named_scope :matching, lambda {|tag_set_to_match|
    {
      :select => "DISTINCT tag_sets.*",
      :joins => :tags,
      :group => 'tag_sets.id',
      :conditions => ["tag_sets.id != ? AND tags.id in (?)", tag_set_to_match.id, tag_set_to_match.tags],
      :order => "count(tags.id) desc"
    }
  }
  
  def has_tag?(tag)
    self.tags.include?(tag)
  end

  
  def with_type(type)
    return self.tags.with_type(type)
  end

  def empty?
    self.tags.empty?
  end
  
  def exact_match?(another)
    self.tags == another.tags
  end
    
  def no_match?(another)
    (self.tags & another.tags).empty? && !self.tags.empty?
  end
  
  def partial_match?(another)
    !(self.tags & another.tags).empty?
  end
  
  def is_subset_of?(another, type=nil)
    if type
      (self.tags.with_type(type) & another.tags.with_type(type)) == self.tags.with_type(type)
    else
      (self.tags & another.tags) == self.tags
    end
  end
  
  def is_superset_of?(another, type=nil)
    if type
      (self.tags.with_type(type) & another.tags.with_type(type)) == another.tags.with_type(type)
    else
      (self.tags & another.tags) == another.tags
    end
  end

  def match_with_type?(another, type)
    (self.tags.with_type(type) & another.tags.with_type(type)) == self.tags.with_type(type)
  end
  
  def partial_match_with_type?(another, type)
    !(self.tags.with_type(type) & another.tags.with_type(type)).empty?
  end
  
  def matching_tags(another)
    self.tags & another.tags
  end
  
  def matching_tags_with_type(another)
    self.tags.with_type(type) & another.tags.with_type(type)
  end
  
  
  ### protected 
  
  protected
    def tagnames_to_list(taglist, type=nil)
      taglist = (taglist.kind_of?(String) ? taglist.split(ArchiveConfig.DELIMITER_FOR_INPUT) : taglist)
      if type
        taglist.reject {|tagname| tagname.blank? }.map {|tagname| (type.classify.constantize).find_or_create_by_name(tagname.squish)}
      else
        taglist.reject {|tagname| tagname.blank? }.map {|tagname| Tag.find_by_name(tagname.squish) || Tag.find_or_create_by_name(tagname.squish)}
      end
    end
  
  
end
