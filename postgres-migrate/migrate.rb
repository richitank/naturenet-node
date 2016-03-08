require "active_record"
require "pg"
require "json"
require "fileutils"

script_root = File.expand_path(File.dirname(__FILE__))

# Saves each record as json into a local `data` directory formatted for firebase
# insertion. A separate node process will then read each file and perform the upload.
#
# For all records except for site we need to translate from the original
# postgres id to an autogenerated firebase one. In order to relink records
# we will need to know both of them locally.
#
# So for every record type except site the name of the file will be the original
# postgres id for the record. As the uploads occur the id's can be rewritten.
#
# We do not need to do this for sites since we are only importing ACES data.
class DataExport

    def self.root
        script_root = File.expand_path(File.dirname(__FILE__))
        return "#{script_root}/data"
    end

    def self.clean
        FileUtils.rm_rf(DataExport.root)
    end

    def self.setup
        DataExport.clean
        Dir.mkdir(DataExport.root)
        Dir.mkdir(DataExport.root + '/sites')
        Dir.mkdir(DataExport.root + '/activities')
        Dir.mkdir(DataExport.root + '/users')
        Dir.mkdir(DataExport.root + '/ideas')
        Dir.mkdir(DataExport.root + '/observations')
    end

    def self.write_site (site)
        File.open(DataExport.root + "/sites/#{site.name}.json", 'w+') do |file|
            file.write(site.aces_firebase_json)
        end
    end

    def self.write_activity (activity)
        File.open(DataExport.root + "/activities/#{activity.id}.json", 'w+') do |file|
            file.write(activity.activity_firebase_json)
        end
    end

end

class Site < ActiveRecord::Base
    self.table_name = 'site'
    has_many :contexts

    # currently only care about aces in the migration
    def self.aces
        Site.includes(:contexts).find_by(name: 'aces')
    end

    def activities
        contexts.reject { |c| c.kind != 'Activity' }
    end

    # The old model didn't keep the site's overall location. Since we're only migrating
    # one site we'll hardcode the conversion here. Still reads the other values from the record.
    def aces_firebase_json
        return JSON.pretty_generate(name: name, description: description, location: [39.1965355,-106.8242489])
    end
end

class Context < ActiveRecord::Base
    self.table_name = 'context'

    # Converts `kind == 'Activity'` records into firebase compatible activities
    # Cannot create and /geo/activities entries since there is no location data
    def activity_firebase_json
        raise "#{name} is not an activity" unless kind == 'Activity'

        extra_data = JSON.parse(extras)
        icon = extra_data['Icon'] || "http://res.cloudinary.com/university-of-colorado/image/upload/v1427400563/2_FreeObservations_mjzgnh.png"

        template = {}
        ['web', 'ios', 'andriod'].each do |key|
            template[key] = extra_data['type'] || 'no data'
        end

        return JSON.pretty_generate(original_id: id, name: title, description: description, icon_url: icon, template: template)
    end
end

class Note < ActiveRecord::Base
    self.table_name = 'note'
    has_one :media

    def self.observations
        Note.includes(:media).where(kind: 'FieldNote')
    end

    def media?
        return media != nil
    end
end

class Media < ActiveRecord::Base
    self.table_name = 'media'

end

# Read the connection url from the .env file in the project root
File.new(script_root + "/../.env").each_line do |line|
    key, value = line.split('=')
    ActiveRecord::Base.establish_connection(value) if key == 'POSTGRES_URL'
end

DataExport.setup

aces = Site.aces
DataExport.write_site(aces)
aces.activities.each { |a| DataExport.write_activity(a) }


=begin
# finding linked photos for observations
Note.observations.find_each do |note|
    if note.media? && note.media.link
        puts "#{note.id} | #{note.kind} #{note.content} #{note.media.link}"
    else
        puts "#{note.id} | #{note.kind} #{note.content}"
    end
end
=end