#!/usr/bin/ruby -w

require 'csv'
require 'byebug'
require 'json'
require 'set'


oldUserTH = 2*30.4
minMeetupReminder = 3
lastCommTH = 30
donationRenewalTH = 365.25-7
userDonatedCount = 0
userDonatedLast12monthCount = 0
amountDonated = 0
amountDonatedLast12months = 0
activeUsers = 0
activeUsersDonated = 0
amountDonatedActiveUser = 0
silentUsers = 0
totalUsers =0


### Calculate the date until next season
seasonBegin = Date.parse("2010-04-13")
seasonBegin = Date.new(Date.today.year, seasonBegin.month, seasonBegin.day)
seasonBegin = Date.new(Date.today.next_year.year, seasonBegin.month, seasonBegin.day) if Date.today >= seasonBegin
skipTH = (seasonBegin - Date.today).to_i
$stderr.puts "skipTH is #{skipTH} days"

### Function to read line from members CSV file
def readTSVline(l)

   seperator="\t"
   if ! ENV['sep'].nil?
      seperator= ENV['sep']
   end

   row = CSV.parse_line(l, :col_sep => seperator).collect{|x|
      if ! x.nil?
          x.strip;
      end
   }

   ### Pick specify elements of that table
   [0, 3, 6, 7, 12, 18, 19, 21].map {|i| row[i]}
end



### First let's make sure there is a membershil list
if ARGV[0].nil? or ARGV[1].nil? then
    $stderr.puts "I need the full path of the file as the first argument and shortfall as second argument."
    exit 1
end

filePath=ARGV[0]
shortfall=ARGV[1].to_f

if ! File.file?(filePath)
    $stderr.puts "There does not seem to be a file at #{filePath}"
    exit 1
end

### ... that is recent
if Time.now() - File.mtime(filePath) > 24*60*60
    $stderr.puts "File is older than 24 hours.  May want to get a fresh membership list."
    exit 1
end


### Parse data for membership list
### Also parse for statistics
users = []
activeNonDonnorsIDs = []
lineCount=0
File.foreach(filePath) { |l|
    lineCount += 1
    next if lineCount == 1

    name, id, lastVisitDate, lastAttendedDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(l)
    totalUsers += 1

    id = id.to_i
    #byebug if id == 9406771
    meetupsAttended = meetupsAttended.to_i

    if lastDonationAmount.nil?
        #lastDonationAmount = 0
    else
        lastDonationAmount = lastDonationAmount.split(' ')[0].to_f
    end

    begin
        lastDonationDate = Date.parse(lastDonationDate) if lastDonationDate
    rescue ArgumentError
        $stderr.puts "Could not parse lastDonationDate '#{lastDonationDate}' on line #{lineCount} (first line 1)"
        exit 1
    end

    begin
        lastVisitDate = Date.parse(lastVisitDate)
    rescue
        puts "Looks like Date.parse didn't like #{lastVisitDate}"
        byebug
        nil
    end

    #byebug
    #Active users statistics
    if (not lastAttendedDate.nil?) and (Date.today - Date.parse(lastAttendedDate) < oldUserTH) and  (meetupsAttended >= minMeetupReminder)
        activeUsers += 1
        if (not lastDonationDate.nil?) and Date.today - lastDonationDate < 367
            amountDonatedActiveUser += lastDonationAmount
            activeUsersDonated += 1
        end
    end

    # Active non donnors monitor
    if (not lastAttendedDate.nil?) and (meetupsAttended >= minMeetupReminder-1) and (lastDonationDate.nil? or Date.today - lastDonationDate >= 366)
        activeNonDonnorsIDs.push id
    end


    #Donors statistics
    if not lastDonationDate.nil?
        userDonatedCount += 1
        byebug if lastDonationAmount.class.name == 'String'
        amountDonated += lastDonationAmount
        if Date.today - lastDonationDate < 365.25
            userDonatedLast12monthCount += 1
            amountDonatedLast12months += lastDonationAmount
        end
    end

    #Silent users
    silentUsers += 1 if (meetupsAttended==0 and lastDonationDate.nil?)

    if meetupsAttended.to_i >= minMeetupReminder and (lastDonationDate.nil? or Date.today - lastDonationDate > donationRenewalTH)
        users.push({ 'name' => name, 'id' => id, 'lastAttendedDate' => Date.parse(lastAttendedDate),
                'lastDonationAmount' => lastDonationAmount, 'lastVisit' => lastVisitDate,
                'meetupsAttended' => meetupsAttended.to_i, 'profileURL' => profileURL,
                'lastDonationDate' => lastDonationDate,
        })
    end
}

#users.sort_by! { |hsh| hsh['lastAttendedDate'] }

users.sort! { |a,b|
    chunkSize = 30.4

    chunkAattend = ((Date.today - a['lastAttendedDate'])/chunkSize).floor;
    chunkBattend = ((Date.today - b['lastAttendedDate'])/chunkSize).floor;
    chunkAvisit = ((Date.today - a['lastVisit'])/chunkSize).floor;
    chunkBvisit = ((Date.today - b['lastVisit'])/chunkSize).floor;

    chunkA = [chunkAattend, chunkAvisit].min
    chunkB = [chunkBattend, chunkBvisit].min


    if chunkA == chunkB
        if chunkAattend != chunkBattend
            chunkAattend - chunkBattend
        elsif chunkAvisit != chunkBvisit
            chunkAvisit - chunkBvisit
        else
            b['meetupsAttended'] - a['meetupsAttended']
        end
    else
        chunkA - chunkB
    end

}

#users.reverse!


users.each { |u|
    puts u
}

#puts users

#exit 0


sleep 1

puts '=' * 72

### Now let's read the communication history file
appDir = File.expand_path("~") + '/.meetupAssist/'

unless File.directory?(appDir)
  FileUtils.mkdir_p(appDir)
end

commHistoryPath = appDir + '/commHistory.txt'

lastCommDates = {}
usersMsgedLast30days = []
notes = Hash.new
skipUsers = []

if File.file?(commHistoryPath)
    File.foreach(commHistoryPath) { |l|
        id, lastComm,skip,userNotes = CSV.parse_line(l)
        lastComm = Date.parse(lastComm)
        id = id.to_i

        notes[id] = userNotes if ! userNotes.nil? and ! userNotes.empty?

        lastCommDates[id] = lastComm

        ### Take not of users we have contacted within last 30 days
        if Date.today - lastComm < lastCommTH
            usersMsgedLast30days.push(id)
        end

        if skip == 'skip' && Date.today - lastComm < skipTH
            skipUsers.push(id)
        end

    }
end



### Read message file
message = File.read(appDir + "reminder.txt")
messageOldParticipants = File.read(appDir + "reminderOldParticipants.txt")



c = File.open(commHistoryPath, 'a');

### Go through each users
quit = false
users.each { |u|
    break if quit
    puts '=' * 72
    puts u['profileURL']
    puts "Meetups attended: #{u['meetupsAttended']}\tLast meetup attended: #{u['lastAttendedDate']}\tLast site visit: #{u['lastVisit']}\tLast comm: #{lastCommDates[u['id'].to_i] if not lastCommDates[u['id'].to_i].nil?}"
    puts "\nNOTES: " + notes[u['id'].to_i] if ! notes[u['id'].to_i].nil?
    puts


    ### Skip if contacted in last 30 days
    if usersMsgedLast30days.include?(u['id'].to_i)
        puts "Skipping #{u['name']} cause recent communcation"
        next
    end

    if skipUsers.include?(u['id'].to_i)
        puts "Skip #{u['name']} cause requested skip"
        next
    end

    if ! lastCommDates[u['id'].to_i].nil?
        if lastCommDates[u['id'].to_i] > u['lastAttendedDate']
            if Date.today - lastCommDates[u['id'].to_i] < lastCommTH*2
                puts "Skipping #{u['name']} cause no attendance since last communication"
                next
            end
        end
    end


    ### Process users not attending last 30 days
    msgContent = message
    lastAttendedDaysAgo = Date.today - u['lastAttendedDate']
    if lastAttendedDaysAgo > oldUserTH

        ### If old user did donate, don't bug them
        if ! u['lastDonationAmount'].nil?
            puts "Skipping #{u['name']} cause user visited #{lastAttendedDaysAgo.to_s} days ago (#{u['lastAttendedDate']}), donated #{u['lastDonationAmount']}"
            next
        else ### If not, prepare message for old participants
            msgContent = messageOldParticipants
        end
    end

    ### Shortfall notice
    shortfallStr = ''
    if shortfall < 0
        shortfallStr = "At the time of this writting, there is a shortfall of #{format("%.2f", shortfall)} $ ."
    end

    ### Prepare thank you note
    thankYouStr = ''
    if ! u['lastDonationAmount'].nil?
        thankYouStr = "\nThank you for your doanation of #{u['lastDonationAmount']} $ last #{u['lastDonationDate'].strftime('%B %-d %Y')}.\n"
    end

    ### Print message
    puts
    puts msgContent.sub('%THANKYOU%', thankYouStr).sub('%NAME%', u['name'].split(' ')[0]).sub('%SHORTFALL%', shortfallStr)
    puts

    #byebug
    ask = true
    notesIn   = ''
    skip    = ''
    while(ask == true) do
        notesTH = 5

        print "Did you write to #{u['name']}? y/n/q/s/* (string longer than #{notesTH} chars will be stored as a note and you will be prompted again) "
        yn = $stdin.gets.chomp

	    if yn == 'y'
            ask = false
	    elsif yn == 'n'
            ask = false
	    elsif yn == 'q'
	        $stderr.puts "Quitting"
            ask = false
            quit = true
            break
	    elsif yn == 's'
            skip = 'skip'
            ask = false
        elsif yn.length > notesTH
            notesIn = "\"#{yn}\""
	    end

        if yn == 'y' or yn == 's'
	        str = "#{u['id']},#{Date.today.to_s},#{skip},#{notesIn}"

    	    $stderr.puts "Adding #{str} to #{commHistoryPath}"
    	    c.puts str
        end
    end


}

c.close()


puts "Total users: #{totalUsers} users"
puts "Silent users: #{silentUsers} users (neither donated or attended)"
puts "Distinct users who have donated: #{userDonatedCount} donors"
puts "Distinct users who have donated last 12 months: #{userDonatedLast12monthCount} donors"
puts "Total last donation: #{amountDonated} $"
puts "Total last donation last 12 months: #{amountDonatedLast12months} $"
puts "Avereage last donation: #{(amountDonated / userDonatedCount).round(2)} $"
puts "Avereage last donation last 12 months: #{(amountDonatedLast12months / userDonatedLast12monthCount).round(2)} $"
puts "Active user: #{activeUsers} users"
puts "Active users donated: #{activeUsersDonated} users"
puts "Total donations active user: #{amountDonatedActiveUser} $"
puts "Average last donation per active user: #{(amountDonatedActiveUser / activeUsers).round(2)} $"


$stderr.puts
$stderr.puts "Finding upcoming active non-donnors...."
$stderr.puts

require 'open-uri'
require_relative appDir + '/config.rb'

url = "https://api.meetup.com/2/events?group_id=#{$groupId}&offset=0&sign=True&format=json&limited_events=False&photo-host=public&page=20&fields=&order=time&status=upcoming&desc=false&key=#{$apiKey}"
$stderr.puts
$stderr.puts "Getting upcoming event info"
$stderr.puts
stringData = open(url).read
open(url).read #Not sure why I have to do this, but otherwise, each second time I run the script, it gets nothign
hash = nil
hash = JSON.parse(stringData) if stringData.length > 2
if hash.nil?
    $stderr.puts "Unable to get event information. String data was:"
    $stderr.puts stringData
    exit 1
end


hash['results'].each { |eventData|
    eventId = eventData['id']
    eventName = eventData['name']
    eventTime = Time.at(eventData['time'].to_i/1000).to_s # + "(#{eventData['time']})"
    eventUrl = eventData['event_url']
    rsvpUrl = "https://api.meetup.com/2/rsvps?event_id=#{eventId}&rsvp=yes&key=#{$apiKey}"

    rsvpDataStr = open(rsvpUrl).read
    rsvpHash = nil

    printedHeader = false
    if rsvpDataStr.length > 2
        rsvpHash = JSON.parse(rsvpDataStr)

        rsvpHash['results'].each { |rsvp|
            if activeNonDonnorsIDs.include?(rsvp['member']['member_id'].to_i)
                if not printedHeader
                    puts
                    puts "For #{eventName} at #{eventTime} (#{eventUrl})"
                end
                printedHeader = true
                puts "#{rsvp['member']['name']} is active, has not donated this year"
            end
        }
    end
}
puts
#CSV.parse_line(l

#     CSV.parse_line(l, :col_sep => seperator).collect{|x|
#        if ! x.nil?
#            x.strip;
#        end
#     }


