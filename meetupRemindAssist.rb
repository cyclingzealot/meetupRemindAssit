#!/usr/bin/ruby -w

require 'csv'
require 'byebug'
require 'json'
require 'set'

require_relative './dates_international.rb'


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
yearCostInCAD = (ARGV[2].to_f or 96.0*2*1.4) # 96 USD / 6 months * 2 * 1.4 high exchange rate


### Calculate the date until next season
seasonBegin = Date.parse("2010-04-13")
seasonBegin = Date.new(Date.today.year, seasonBegin.month, seasonBegin.day)
seasonBegin = Date.new(Date.today.next_year.year, seasonBegin.month, seasonBegin.day) if Date.today >= seasonBegin
skipTH = (seasonBegin - Date.today).to_i
$stderr.puts "skipTH is #{skipTH} days"


### Function to detect sep
    def self.detectSeperator(filePath)
        seperators = [';', ':', "\t", ',', '|']
        firstLine = File.open(filePath, &:readline)

        seperators.max_by{ |s|
            firstLine.split(s).count
        }
    end


### Function to read line from members CSV file
def readTSVline(l, sep=nil)

    sep = detectSeperator if sep.nil?

   #row = CSV.parse_line(l, :col_sep => seperator).collect{|x|
   row = l.split(sep).collect{|x|
      if ! x.nil?
          x.strip;
      end
   }

   ### Pick specify elements of that table
    #name, id, lastVisitDate, lastAttendedDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(seperator)
   [0, 3, 6, 7, 12, 18, 19, 21].map {|i| row[i]}
end



### First let's make sure there is a membershil list
if ARGV[0].nil? or ARGV[1].nil? then
    $stderr.puts "I need the full path of the file as the first argument and shortfall as second argument."
    exit 1
end

filePath=ARGV[0]
shortfall=ARGV[1].to_f

### If the shortfall is positive, then we can increase threholds
ratio=1
if shortfall >= yearCostInCAD
    ratio = shortfall / yearCostInCAD
    minMeetupReminder   *= ratio
    lastCommTH          *= ratio
    donationRenewalTH   *= ratio

    puts "Thresholds have been increased by #{ratio.round(2)}"
    puts "minMeetupReminderTH: #{minMeetupReminder.round(1)}   lastCommTH: #{lastCommTH.round(1)}   donationRenewalTH: #{donationRenewalTH.round(1)}"
    sleep 1
end

if ! File.file?(filePath)
    $stderr.puts "There does not seem to be a file at #{filePath}"
    exit 1
end

### ... that is recent
if Time.now() - File.mtime(filePath) > 24*60*60
    $stderr.puts "File is older than 24 hours.  May want to get a fresh membership list."
    exit 1
end


seperator=detectSeperator(filePath)


### Parse data for membership list
### Also parse for statistics
users = []
activeNonDonnorsIDs = []
lineCount=0
errorDuringProcessing = []
File.foreach(filePath) { |l|
begin
    lineCount += 1
    next if lineCount == 1

    #byebug if lineCount < 3
    name, id, lastVisitDate, lastAttendedDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(l, seperator)

    totalUsers += 1

    id = id.to_i
    meetupsAttended = meetupsAttended.to_i

    begin
	    if lastDonationAmount.empty?
	        lastDonationAmount = nil
	        lastDonationDate = nil
	    else
	        lastDonationAmount = lastDonationAmount.split(' ')[0].to_f
	        lastDonationDate = Date.parse_international(lastDonationDate) if not lastDonationDate.empty?
	    end
    rescue ArgumentError
        $stderr.puts "Could not parse lastDonationDate '#{lastDonationDate}' on line #{lineCount} (first line 1)"
        byebug if errorDuringProcessing.count < 4
        raise
    end


    begin
        lastVisitDate = Date.parse_international(lastVisitDate)
    rescue => e
        $stderr.puts "Could not parse lastVisitDate '#{lastVisitDate}' on line #{lineCount} (first line 1)"
        byebug if errorDuringProcessing.count < 4
        raise
    end

    lastAttendedDate = Date.parse_international(lastAttendedDate) if not lastAttendedDate.empty?

    #Active users statistics
    begin
	    if (lastAttendedDate.class == Date) and (Date.today - lastAttendedDate < oldUserTH) and  (meetupsAttended >= minMeetupReminder)
	        activeUsers += 1
	        if (lastDonationDate.class == Date) and Date.today - lastDonationDate < 367
	            amountDonatedActiveUser += lastDonationAmount
	            activeUsersDonated += 1
	        end
	    end
    rescue => e
        byebug if errorDuringProcessing.count < 4
        raise
    end

    # Active non donnors monitor
    if (lastAttendedDate.class == Date) and (meetupsAttended >= minMeetupReminder-1) and (lastDonationDate.class != Date or Date.today - lastDonationDate >= 366)
        activeNonDonnorsIDs.push id
    end


    #Donors statistics
    if lastDonationDate.class == Date
        userDonatedCount += 1
        amountDonated += lastDonationAmount
        if Date.today - lastDonationDate < 365.25
            userDonatedLast12monthCount += 1
            amountDonatedLast12months += lastDonationAmount
        end
    end

    #Silent users
    silentUsers += 1 if (meetupsAttended==0 and lastDonationDate.class != Date)

    if meetupsAttended.to_i >= minMeetupReminder and (lastDonationDate.class != Date or Date.today - lastDonationDate > donationRenewalTH)
        byebug if lastDonationDate == ""
        users.push({ 'name' => name, 'id' => id, 'lastAttendedDate' => lastAttendedDate,
                'lastDonationAmount' => lastDonationAmount, 'lastVisit' => lastVisitDate,
                'meetupsAttended' => meetupsAttended.to_i, 'profileURL' => profileURL,
                'lastDonationDate' => lastDonationDate,
        })
    end

rescue => e
    byebug if errorDuringProcessing.count < 4
    errorDuringProcessing.push(l)
    next
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
    require 'fileutils'
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
    puts "minMeetupReminderTH: #{minMeetupReminder.round(1)}   lastCommTH: #{lastCommTH.round(1)}   donationRenewalTH: #{(donationRenewalTH/365.25).round(2)} y" if ratio > 1
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
        thankYouStr = "\nThank you for your donation"
        thankYouStr +=" of #{u['lastDonationAmount']} $" if u['lastDonationAmount'].to_f >= 1
        thankYouStr += " last #{u['lastDonationDate'].strftime('%B %-d %Y')}.\n"

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

puts "WARNING: #{errorDuringProcessing.count} users not processed" if errorDuringProcessing.count > 0

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


puts
#CSV.parse_line(l

#     CSV.parse_line(l, :col_sep => seperator).collect{|x|
#        if ! x.nil?
#            x.strip;
#        end
#     }


