#!/usr/bin/ruby -w

require 'csv'
require 'byebug'

oldUserTH = 6*30.4
minMeetupReminder = 3
lastCommTH = 21


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
users = []
lineCount=0
File.foreach(filePath) { |l|
    lineCount += 1
    next if lineCount == 1

    name, id, lastVisitDate, lastAttendedDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(l)

    lastDonationDate = Date.parse(lastDonationDate) if lastDonationDate

    lastVisitDate = Date.parse(lastVisitDate)

    if meetupsAttended.to_i >= minMeetupReminder and (lastDonationDate.nil? or Date.today - lastDonationDate > 365.25 - 30.4)
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

usersMsgedLast30days = []
notes = Hash.new
skipUsers = []

if File.file?(commHistoryPath)
    File.foreach(commHistoryPath) { |l|
        id, lastComm,skip,userNotes = CSV.parse_line(l)

        lastComm = Date.parse(lastComm)

        notes[id.to_i] = userNotes if ! userNotes.nil? and ! userNotes.empty?

        ### Take not of users we have contacted within last 30 days
        if Date.today - lastComm < lastCommTH
            usersMsgedLast30days.push(id.to_i)
        end

        if skip == 'skip' && Date.today - lastComm < skipTH
            skipUsers.push(id.to_i)
        end

    }
end



### Read message file
message = File.read(appDir + "reminder.txt")
messageOldParticipants = File.read(appDir + "reminderOldParticipants.txt")



c = File.open(commHistoryPath, 'a');

### Go through each users
users.each { |u|
    puts '=' * 72
    puts u['profileURL']
    puts "Meetups attended: #{u['meetupsAttended']}\tLast meetup attended: #{u['lastAttendedDate']}\tLast site visit: #{u['lastVisit']}"
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
        thankYouStr = "\nThank you for your doanation of #{u['lastDonationAmount'].sub('USD', '$')} last #{u['lastDonationDate']}.\n"
    end

    ### Print message
    puts
    puts msgContent.sub('%THANKYOU%', thankYouStr).sub('%NAME%', u['name'].split(' ')[0]).sub('%SHORTFALL%', shortfallStr)
    puts

    #byebug
    ask = TRUE
    notesIn   = ''
    skip    = ''
    while(ask == TRUE) do
        notesTH = 5

        print "Did you write to #{u['name']}? y/n/q/s/* (string longer than #{notesTH} chars will be stored as a note and you will be prompted again) "
        yn = $stdin.gets.chomp

	    if yn == 'y'
            ask = FALSE
	    elsif yn == 'n'
            ask = FALSE
	    elsif yn == 'q'
	        $stderr.puts "Quitting"
            ask = FALSE
            exit 0
	    elsif yn == 's'
            skip = 'skip'
            ask = FALSE
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


#CSV.parse_line(l

#     CSV.parse_line(l, :col_sep => seperator).collect{|x|
#        if ! x.nil?
#            x.strip;
#        end
#     }


