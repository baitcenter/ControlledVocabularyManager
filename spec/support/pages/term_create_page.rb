class TermCreatePage < Struct.new(:vocabulary_id)
  include Capybara::DSL

  def visible?
    has_content? "Create New Term"
  end

  def create
    fill_in "ID", :with => "banana"
    fill_in "vocabulary[label][]", :with => "Test label"
    fill_in "vocabulary[comment][]", :with => "Test comment"
    click_button "Create Term"
    TermShowPage.new(id)
  end

  def id
    "#{vocabulary_id}/banana"
  end
end
