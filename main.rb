#!/usr/bin/ruby -w

require 'csv'

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
     [0, 6, 12, 18, 19, 21].map {|i| row[i]}
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


users = []

lineCount=0
File.foreach(filePath) { |l|
    lineCount += 1
    next if lineCount == 1

    name, lastVisitDate, meetupsAttended, profileURL, lastDonationAmount, lastDonationDate = readTSVline(l)

    lastDonationRealDate = nil
    lastDonationRealDate = Date.parse(lastDonationDate) if lastDonationDate

    if meetupsAttended.to_i > 3 and (lastDonationRealDate.nil? or Date.today - lastDonationRealDate > 365)
        users.push({'name' => name, 'meetupsAttended' => meetupsAttended, 'profileURL' => profileURL})
    end
}


users.sort_by! { |hsh| hsh['meetupsAttended'].to_i }
users.reverse!

puts users



#CSV.parse_line(l

#     CSV.parse_line(l, :col_sep => seperator).collect{|x|
#        if ! x.nil?
#            x.strip;
#        end
#     }


