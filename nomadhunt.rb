require "json"
require "open-uri"
require 'mailchimp'
require 'yaml'
require 'logger'

logger = Logger.new('nomadhunt.log')

File.open("cities_already_discovered.txt", "a+") do |f|
	cities_already_discovered = f.readlines.map { |c| c.strip }
	cities = JSON.parse(open("http://nomadlist.io/api/v1").read)['cities']
	cities_slug = cities.map { |city| city['slug'] }
	new_cities = []
	cities_slug.each do |city|
		if !cities_already_discovered.include?(city)
			new_cities << city
		end
	end

	if cities_already_discovered.size > 0 and new_cities.size > 0
		new_cities.each do |new_city_slug|
			city = cities.find { |c| c["slug"] == new_city_slug }
			# Send a campaign to NomadHunt List
			begin
				# Load config
				mailchimp_config = YAML.load_file('.mailchimp.yml')

				# Retrieve list
				mailchimp = Mailchimp::API.new(mailchimp_config["API_KEY"])
				list = mailchimp.lists.list({ 'id' => mailchimp_config["LIST_ID"] })['data'].first

				# Prepare body
				html = "
					<p>
						Hi!<br/>
						<br/>
						I just wanted to inform you that a new city is available for digital nomad on NomadList.<br/>
					</p>
					<p>	
						<a href='http://nomadlist.io/#{city['slug']}?utm_source=nomadhunt'>Click here to discover #{city['name']}</a>:
						<ul>
							<li>Score on NomadList: #{city['nomadScore']}</li>
							<li>NomadCost: #{city['nomadCost']['EUR']}€ / #{city['nomadCost']['USD']}$</li>
							<li>Temperature: #{city['temperature']['c']}°C / #{city['temperature']['f']}°F</li>
						</ul>
					</p>
					<p>
						Bye,<br/>
						#{list['default_from_name']}.
					</p>
				"
				text = "Hi!\nNew city available on NomadList : http://nomadlist.io/#{city['slug']}?utm_source=nomadhunt\nBye,\n#{list['default_from_name']}."

				# Create a new campaign
				campaign = mailchimp.campaigns.create(
					'regular', 
					{ 
						'list_id' => mailchimp_config["LIST_ID"], 
						'subject' => "[NomadHunt] Discover " << city["name"] << " (" << city["country"] << ") on NomadList" , 
						'from_email' => list['default_from_email'],
						'from_name' => list['default_from_name']
					},
					{ 
						'html' => html,
						'text' => text
					}
				)

				# Send the campaign if it's ready!
				mailchimp.campaigns.send(campaign["id"]) if mailchimp.campaigns.ready(campaign["id"])["is_ready"]

				# Log the new city in the file
				f.puts city["slug"]
				logger.info("Campaign #" << campaign["id"] << " launched for " << city["name"])

			rescue Exception => e
				logger.fatal e.message
			end
		end
	end
end

logger.close