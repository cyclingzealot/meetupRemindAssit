#!/usr/bin/ruby -w

require 'csv'
require 'byebug'

  def readTSVline(l)

     seperator=','
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

if ARGV[0].nil? then
    $stderr.puts "I need the full path of the file as the first argument"
    exit 1
end

filePath=ARGV[0]

if ! File.file?(filePath)
    $stderr.puts "There does not seem to be a file at #{filePath}"
    exit 1
end

if Time.now() - File.mtime(filePath) > 24*60*60
    $stderr.puts "File is older than 24 hours.  May want to get a fresh membership list."
    exit 1
end


users = []

lineCount=0
File.foreach(filePath) { |l|
    lineCount += 1
    next if lineCount == 1

    name, id, lastVisitDate, lastAttendedDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(l)

    lastDonationDate = Date.parse(lastDonationDate) if lastDonationDate

    lastVisitDate = Date.parse(lastVisitDate)

    if meetupsAttended.to_i > 3 and (lastDonationDate.nil? or Date.today - lastDonationDate > 365)
        users.push({ 'name' => name, 'id' => id, 'lastAttendedDate' => Date.parse(lastAttendedDate),
                'lastDonationAmount' => lastDonationAmount, 'lastVisit' => lastVisitDate,
                'meetupsAttended' => meetupsAttended, 'profileURL' => profileURL,
                'lastDonationDate' => lastDonationDate,
        })
    end
}


users.sort_by! { |hsh| hsh['lastAttendedDate'] }
users.reverse!

#puts users

#exit 0

appDir = File.expand_path("~") + '/.meetupAssist/'

unless File.directory?(appDir)
  FileUtils.mkdir_p(appDir)
end

commHistoryPath = appDir + '/commHistory.txt'

usersMsgedLast30days = []

if File.file?(commHistoryPath)
    File.foreach(commHistoryPath) { |l|
        id, lastComm = CSV.parse_line(l)

        lastComm = Date.parse(lastComm)

        if Date.today - lastComm < 30.4
            usersMsgedLast30days.push(id.to_i)
        end
    }
end

message = File.read(appDir + "reminder.txt")
messageOldParticipants = File.read(appDir + "reminderOldParticipants.txt")

c = File.open(commHistoryPath, 'a');

users.each { |u|
    puts '=' * 72
    puts u['profileURL']
    if usersMsgedLast30days.include?(u['id'].to_i)
        puts "Skipping #{u['name']} cause recent communcation"
        next
    end

    msgContent = message
    lastVisitDaysAgo = Date.today - u['lastAttendedDate']
    if lastVisitDaysAgo > 6*30.4
        if ! u['lastDonationAmount'].nil?
            puts "Skipping #{u['name']} cause user visited #{lastVisitDaysAgo.to_s} days ago (#{u['lastAttendedDate']}), donated #{u['lastDonationAmount']}"
            next
        else
            msgContent = messageOldParticipants
        end
    end

    thankYouStr = ''
    if ! u['lastDonationAmount'].nil?
        thankYouStr = "\nThank you for your doanation of #{u['lastDonationAmount'].sub('USD', '$')} last #{u['lastDonationDate']}.\n"
    end

    puts
    puts msgContent.sub('%THANKYOU%', thankYouStr).sub('%NAME%', u['name'].split(' ')[0])
    puts

    print "Did you write to #{u['name']}? y/n/q "
    yn = $stdin.gets.chomp

    #byebug
    if yn != 'n' and yn != 'q'
        str = "#{u['id']},#{Date.today.to_s}"
        $stderr.puts "Adding #{str} to #{commHistoryPath}"
        c.puts str
    elsif yn == 'q'
        $stderr.puts "Quitting"
        break
    end


}


#CSV.parse_line(l

#     CSV.parse_line(l, :col_sep => seperator).collect{|x|
#        if ! x.nil?
#            x.strip;
#        end
#     }


