class Vocabulary < Term
  configure :type => RDF::URI("http://purl.org/dc/dcam/VocabularyEncodingScheme")
  property :title, :predicate => RDF::DC.title
  property :publisher, :predicate => RDF::DC.publisher

  def self.option_text
    "Vocabulary"
  end

  def self.uri
    self.type.to_s
  end

  def self.visible_form_fields
    %w[label alternate_name date comment is_replaced_by is_defined_by same_as modified issued title publisher]
  end

  def allow_vocab_deprecate?
    deprecated_children.length == vocab_with_children.length
  end

  # Update the fields method with any new properties added to this model
  def fields
    [:title, :publisher] | super
  end

  private

  def deprecated_children
    vocab_with_children.select { |c| c.deprecated? }
  end

  def vocab_with_children
    injector = TermInjector.new
    vocab = TermWithChildren.new(self, injector.child_node_finder)
    vocab.children
  end

end
