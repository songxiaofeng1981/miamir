#encoding: utf-8
class Task < ActiveRecord::Base
  attr_accessible :redmine_assigned_to_id,:redmine_issue_id,:team_id, :team, :partner, :owner, :priority, :scale, :estimate, :description, :status, :title

  default_scope order('priority DESC')

  belongs_to :owner, :class_name=>"User", :foreign_key=>"owner_id"
  belongs_to :partner, :class_name=>"User", :foreign_key=>"partner_id"
  belongs_to :team

  has_many :durations,:dependent => :delete_all

  before_save :default_values

  validate :user_own_only_one_task,:progress_must_be_estimated,:ready_must_has_scale

  def self.emptying
    Task.logger.debug("emptying start...")
      tasks = Task.where(:status=>'Progress')
      tasks.each do |task|
        task.status = 'Ready'
        duration = task.durations.where(:minutes=>0).first
        if !duration.nil?
          working_minutes = ((Time.now.change(:hour=>18)-duration.created_at)/1.minute).ceil
          duration.minutes = (working_minutes <= 0 )? 60 : working_minutes
          duration.save()
        end
        task.save(:validate=>false)
      end
    Task.logger.debug("emptying end...")
  end

  def serializable_hash(options={})
    options = { 
      :methods => [:consuming],
      :include => {:owner=> {:methods => [:short_name],:except => [:created_at, :updated_at]},:partner => { :methods => [:short_name],:except => [:created_at, :updated_at]}}
    }.update(options)
    super(options)
  end

  def consuming()
    self.durations.inject(0) {|sum, n| sum + n[:minutes] }
  end

  #参与者
  def participants()
    participants = self.durations.joins(:owner).select('`users`.`gravatar` as gravatar ,sum(minutes) as total').group('`users`.`gravatar`')
    partners = self.durations.joins(:partner).select('`users`.`gravatar` as gravatar ,sum(minutes) as total').group('`users`.`gravatar`')
    if not partners.empty?
      participants += partners
    end
    return participants
  end

  def checkin(user)
    Task.transaction do
      self.durations.create!(:owner=>user)
      self.update_attributes!(:owner=>user,:status=>'Progress')
    end
  end

  def checkout(user,status='Ready')
    Task.transaction do
      duration = self.durations.where(:owner_id=>user.id,:minutes=>0).first
      duration.update_attributes!(:minutes=>((Time.now-duration.created_at)/1.minute).ceil) if duration
      self.update_attributes!(:owner=>nil,:partner=>nil,:status=>status)
    end
  end

  def done(user)
    self.checkout(user,'Done')
  end

  def cancel()
    Task.transaction do
      self.update_attributes!(:status=>'New')
    end
  end

  def pair(user)
    Task.transaction do
      duration = self.durations.where(:owner_id=>self.owner.id,:minutes=>0).first
      duration.update_attributes(:minutes=>((Time.now-duration.created_at)/1.minute).ceil) 
      self.durations.create!(:owner=>self.owner,:partner=>user)
      self.update_attributes!(:partner=>user)
    end
  end

  def leave(user)
    Task.transaction do
      duration = self.durations.where(:partner_id=>user.id,:minutes=>0).first
      duration.update_attributes(:minutes=>((Time.now-duration.created_at)/1.minute).ceil)
      self.durations.create!(:owner=>self.owner,:partner=>nil)
      self.update_attributes(:partner=>nil)
    end
  end

  private 
    def default_values
      self.estimate ||= 0
      self.scale ||= 0
      self.status ||='New'
      if self.status == 'Progress'
        self.redmine_assigned_to_id = self.owner.redmine_user_id
      end
    end

    def user_own_only_one_task
      if partner
        if (status=='Progress') and (!partner.idle?) and (partner.partnership!=self)
          errors[:duplicate_task]<<"user own only one task"
        end
      else
        if (status=='Progress') and (!owner.idle?) and (owner.task!=self)
          errors[:duplicate_task]<<"user own only one task"
        end
      end
    end

    def progress_must_be_estimated
      if (status=='Progress') and (estimate == 0)
        errors[:estimate]<<"progress must be estimated"
      end
    end

    def ready_must_has_scale
      if (status=='Ready') and (scale == 0)
        errors[:scale]<<"progress must be scale"
      end
    end

end
