module GitInterface
  extend ActiveSupport::Concern
  require 'rugged'

  def rugged_create (id, string, action)
    begin
    branch_id = branchify(id)
      repo = setup
      #find/create branch and check it out
      branch = repo.branches[branch_id]
      if branch.nil?
        branch = repo.branches.create(branch_id, "HEAD")
      end
      repo.checkout(branch)
      #add blob
      oid = repo.write(string,:blob)
      index = repo.index
      index.read_tree(repo.head.target.tree)
      index.add(:path => "#{id}.nt", :oid => oid, :mode => 0100644)
      #commit
      options = get_base_options
      options[:tree] = index.write_tree(repo)
      options[:message] = action + ": " + id
      options[:parents] = repo.empty? ? [] : [ repo.head.target ].compact
      Rugged::Commit.create(repo, options)
      index.write
      options = {}
      options[:strategy] = :force
      repo.checkout_head(options)
      repo.checkout('master')
    rescue
      logger.error("Git create failed. Refer to " + branch_id)
    end
  end

  def get_base_options
    options = {}
    options[:author] = { :email => current_user.email, :name => current_user.name, :time => Time.now }
    options[:committer] = { :email => current_user.email, :name => current_user.name, :time => Time.now }
    options[:update_ref] = 'HEAD'
    options
  end

  def rugged_merge (id)
    begin
    branch_id = branchify(id)
      repo = setup
      #merge
      into_branch = 'master'
      from_branch = branch_id
      their_commit = repo.branches[into_branch].target_id
      our_commit = repo.branches[from_branch].target_id

      merge_index = repo.merge_commits(our_commit, their_commit)

      if merge_index.conflicts?
        logger.error('merge conflict with branch: ' + branch_id)
        raise 'merge conflict'
      else
        commit_tree = merge_index.write_tree(repo)
        options = get_base_options
        options[:tree] = commit_tree
        options[:message] ||= "Merge #{from_branch} into #{into_branch}"
        options[:parents] = [repo.head.target, our_commit]

        Rugged::Commit.create(repo, options)
        repo.checkout_tree(commit_tree)
        index = repo.index
        index.write
        options = {}
        options[:strategy] = :force
        repo.checkout_head(options)
        #repo.push('origin', [repo.head.name], { credentials: @cred })
      end
    return our_commit
    rescue
      return 0
    end
  end

  def rugged_delete_branch(id)
    branch_id = branchify(id)
    begin
      repo = setup
      repo.branches.delete(branch_id)
    rescue
      logger.error('delete_branch failed, refer to: ' + branch_id)
    end
  end

  def rugged_rollback (branch_commit)
    begin
      repo = setup
      if branch_commit == repo.last_commit.parents[1].oid
        oid = repo.last_commit.parents[0].oid
        repo.reset(oid, :hard)
      else
        logger.error('rollback not attempted. refer to: ' + branch_commit)
      end
    rescue
      logger.error('rollback failed. refer to: ' + branch_commit)
    end
  end

  def setup
    repo = Rugged::Repository.new(ControlledVocabularyManager::Application::config.rugged_repo)
    if !repo.head.name.include? "master"
      repo.checkout('master')
    end
    repo
  end

  def get_history(id, branch="master")
    repo = setup
    path = id + ".nt"
    info = commit_info_rugged(repo, path, branch)
    formatted = format_response(info)
    formatted
   end

  #refer to rugged issue 343
  def entry_changed?(commit, path, repo)
    if path.include? "/"
      term = WalkerTerm.new(commit, path, repo)
    else
      term = WalkerVocab.new(commit, path, repo)
    end

    # if at a root commit, consider it changed if we have the file
    # i.e. if we added it in the initial commit
    if not term.parent
      return term.record != nil
    end

    # does not exist in either, no change
    if not term.record and not term.parent_record
      false
    # exists only in one of them, change
    elsif not term.record or not term.parent_record then
      true
    # otherwise it's changed if their ids aren't the same
    else
      term.record[:oid] != term.parent_record[:oid]
    end
  end

  def commit_info_rugged(repo, path, branch_name)

    walker = Rugged::Walker.new(repo)
    walker.sorting(Rugged::SORT_DATE)
    if branch_name != "master"
      branch = repo.lookup(repo.branches[branch_name].target_id)
    else
      branch = repo.last_commit
    end
    walker.push(branch)
    walker.inject([]) do |a, c|
      if entry_changed? c, path, repo
         a << {author: c.author, date: c.time, hash: c.oid, message: c.message}
      end
      a
    end
  end

  #returns an array of triple as strings with "added" or "deleted" prefixes
  def get_diff(commit1)
    answer = []
    repo = setup
    child = repo.lookup(commit1)
    commits = child.parents[0].diff(child)
    commits.each_patch do |patch|
      file = patch.delta.old_file[:path]

      patch.each_hunk do |hunk|
        hunk.each_line do |line|
          case line.line_origin
          when :addition
            answer << "added: " + line.content
          when :deletion
            answer << "deleted: " + line.content
          when :context
            #do nothing
          end
        end
      end
    end
    answer
  end

  def format_response(results)

    if results.empty?
      return
    else
      formatted = []
      num_items = 1
      results.each do |commit|
        if commit[:message].include? "updating"
          diffs = get_diff(commit[:hash])
          newdiffs = []
          #remove subject
          diffs.each do |diff|
            parts = diff.split("<")
            newparts = parts.slice(0,1).concat(parts.slice(2, parts.length-1))
            newdiffs << newparts.join("<")
          end
          item = {:date => commit[:date], :author => commit[:author][:name], :diff => newdiffs }
          formatted << item
          num_items = num_items + 1
        end
        break if num_items > 3
      end
      if formatted.empty?
        return nil
      end
      formatted
    end
  end

 def branch_list
    repo = setup
    branches = repo.branches.each_name(:local).sort
    branches = branches.reject{|branch| branch == 'master'}
  end

  #retrieve the data from git
  #for use in review queue/show
  def commit_content(branchname)

    begin
      repo = setup
      id = unbranchify(branchname)
      branch = repo.lookup(repo.branches[branchname].target_id)
      if(id.include?"/")
        parts = id.split("/")
        vocabtree = repo.lookup(branch.tree[parts[0]][:oid])
        commit = repo.lookup(vocabtree[parts[1]+ ".nt"][:oid])
      else
        commit = repo.lookup(branch.tree[id + ".nt"][:oid])
      end
      commit.content
    rescue
      nil
    end
  end

  #creates an array of terms
  #for use in review process
  def review_list
    terms = []
    branches = branch_list
    branches.each do |branch|
      content = commit_content(branch)
      if !content.blank?
        graph = triples_string_to_graph(content)
        label_state = graph.query([nil, RDF::RDFS.label, nil])
        if !label_state.blank?
          label = label_state.first.object.to_s
          uri = label_state.first.subject.to_s
        else
          uri = graph.first.subject.to_s
          label = graph.first.subject.to_s
        end
        terms << {:id => unbranchify(branch), :uri => uri, :label => label}
      end
    end
    terms
  end

  #takes string and converts to rdf statement
  def triple_string_to_statement(tstring)
    reader = RDF::Reader.for(:ntriples).new(tstring)
    reader.first
  end

  #takes string .nt and converts to graph
  def triples_string_to_graph(tstring)
    graph = RDF::Graph.new
    RDF::Reader.for(:ntriples).new(tstring) do |reader|
      reader.each_statement do |statement|
        graph << statement
      end
    end
    graph
  end


  def get_graph(branchname)
    content = commit_content(branchname)
    graph = triples_string_to_graph(content)
  end

  #reassembles rdf graph from git
  def reassemble(id)
    branchname = branchify(id)
    graph = get_graph(branchname)
    statements = graph.query(:predicate=>RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"))
    if statements.any? { |s| s.object == RDF::URI("http://purl.org/dc/dcam/VocabularyEncodingScheme") }
      sr = StandardRepository.new(nil, Vocabulary)
    elsif statements.any? { |s| s.object == RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#predicate") }
      sr = StandardRepository.new(nil, Predicate)
    else
      sr = StandardRepository.new(nil, Term)
    end
    results = GraphToTerms.new(sr, graph).terms
    results.first
  end

  #reassembles params from git
  # for repopulating edit forms
  def edit_params (id)
    term = reassemble(id)
    proplangs = Hash.new
    vocabhash = Hash.new
    Vocabulary.properties.each do |property|
      results = []
      term.query(:predicate=> property[1].predicate ).each_statement {|s,p,o| results << o }
      if !results.empty?
        if !term.blacklisted_language_properties.include? property[0].to_sym
          if results.first.respond_to? :language
            proplangs[property.first.to_s] = [results.first.language.to_s]
          end
        end
        vocabhash[property.first.to_sym] = [results.first.object.to_s]
      end
    end
    vocabhash[:language] = proplangs
    params = Hash.new
    params[:vocabulary] = vocabhash
    params
  end

  def branchify(id)
    id + "_review"
  end

  def unbranchify(branch)
    if branch.ends_with? "_review"
      branch.slice(0..-8)
    else
      branch
    end
  end

  class WalkerTerm
    attr_reader :record, :parent, :parent_record

    def initialize (commit, path, repo)
      arr = path.split "/"
      voc_id = arr[0]
      term_id = arr[1]
      if !commit.tree[voc_id].nil?
        childtree = repo.lookup(commit.tree[voc_id][:oid])
        @record = childtree[term_id]
      else
        @record = nil
      end
      @parent = commit.parents[0]
      if !@parent.nil? && !@parent.tree[voc_id].nil?
        parenttree = repo.lookup(@parent.tree[voc_id][:oid])
        @parent_record = parenttree[term_id]
      else
        @parent_record = nil
      end
    end
  end

  class WalkerVocab
    attr_reader :record, :parent, :parent_record

    def initialize(commit, path, repo)
      voc_id = path
      @record = commit.tree[voc_id]
      @parent = commit.parents[0]
      if !@parent.nil?
        @parent_record = parent.tree[voc_id]
      end
    end
  end

end
