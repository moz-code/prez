# Copyright 2019 Alexandre Terrasa <alexandre@moz-code.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module prez

import github2
import template::macro

class Prez

	var token_file = "token" is optional

	var token: String is lazy do
		var path = token_file.to_path
		assert path.exists
		return path.read_all.trim
	end

	var api = new API(token, "prez") is lazy

	var org: String = "moz-code"
	var owner: String = "Morriar"
	var school: String = "ETS"
	var owner_email: String = "alexandre@moz-code.org"
	var year: Int = 2020
	var tpl_slug: String = "csgames/co-2020"
	var tpl_readme: String = "README.tpl"
	var team_name = "CO-{year}"
	var team_parent = "CO"
	var links = ["a", "b"]

	var repo_name = "co-{year}"
	var repo_slug = "{org}/{repo_name}"

	var co: Map[String, GitUser] is lazy do
		var co = new HashMap[String, GitUser]
		co["Finances"] = new GitUser("Morriar", "alexandre@moz-code.org")
		return co
	end

	var coaches: Map[String, GitUser] is lazy do
		var co = new HashMap[String, GitUser]
		co["Finances"] = new GitUser("Morriar", "alexandre@moz-code.org")
		return co
	end

	fun run do
		# TODO options
		# TODO config
		# TODO change attributes by parameters

		# Get CO parent team
		# var parent = api.get_team(org, team_parent)
		# assert parent != null

		# Get template repository
		# var tpl_repo = api.get_repo(tpl_slug)

		# var team = create_team(parent)
		# var repo = create_repo(team)
		# clear_labels
		# create_labels
		# create_readme
	end

	fun create_team(parent: nullable Team): Team do
		print "Create team {team_name}..."

		# Try team
		var team = api.get_team(org, team_name)
		if team != null then return team

		# Create CO team
		var post = new Team(
			name = "CO-{year}",
			maintainers = [owner],
			repo_names = [repo_slug],
			privacy = "closed"
		)
		if parent != null then
			post.parent_team_id = parent.id
		end
		var res = api.post_team(org, post)
		check_error
		return res.as(not null)
		# TODO add team members
	end

	# TODO SET OWNER ME
	# TODO set team admin
	fun create_repo(team: nullable Team): Repo do
		print "Create repo {repo_slug}..."
		var repo = api.get_repo(repo_slug)
		if repo != null then return repo

		var post = new PostRepo(
			name = repo_name,
			description = "Suivi CSGames {year}",
			homepage = "http://2019.csgames.org",
			# TODO change repo public visiblity to private
			# is_private = true,
			is_private = false,
			has_issues = true,
			has_projects = true,
			has_wiki = true,
			auto_init = false
		)
		if team != null then
			post.team_id = team.id
		end
		var res = api.post_repo_org(org, post)
		check_error
		return res.as(not null)
	end

	fun clear_labels do
		print "Delete labels..."
		var labels = api.get_repo_labels(repo_slug)
		check_error
		if labels == null then return
		for lbl in labels do
			if not (lbl.default or else false) then continue
			print "Delete label {lbl.name}..."
			api.delete_label(repo_slug, lbl.name)
		end
	end

	fun create_labels do
		print "Create labels..."
		var labels = api.get_repo_labels(tpl_slug)
		check_error
		if labels == null then return
		for lbl in labels do
			print "Create label {lbl.name}..."
			api.post_label(repo_slug, lbl)
		end
	end

	# TODO Create project
	# TODO columns (TODO, In Progress, Done)
	fun create_project do
	end

	# TODO Create milestones: avril 2020 -> avril 2021
	fun create_milestones do
		# TODO  read from config
	end

	fun create_issues do
		# var issues = api.get_issues(tpl_slug)
		# for issue in issues do
			# var post = new PostIssue(
				# title = issue.title,
				# body = issue.body
				# # TODO assignees,
				# # TODO milestone
				# # TODO labels
			# )
			# api.post_issue(repo_slug, post)
			# check_error
		# end
	end

	fun create_readme do
		var content = "CONTENT"
		var tpl = new TemplateString.from_file(tpl_readme)
		tpl.replace("YEAR", year.to_s)
		tpl.replace("SCHOOL", school)
		tpl.replace("CO", tpl_co)
		tpl.replace("LINKS", tpl_links)
		var user = new GitUser(owner, owner_email)
		var file = new FilePost(
			message = "Initialize repo",
			content = content,
			committer = user
		)
		api.put_file(repo_slug, "README.md", file)
	end

	fun tpl_co: Template do
		var tpl = new Template
		for role, user in co do
			var url = "https://github.com/{repo_slug}/labels/{role}"
			tpl.addn "* [{role}]({url}): @{user.name or else "n/a"} (coach: @{coaches[role].name or else "n/a"})"
		end
		return tpl
	end

	fun tpl_links: Template do
		var tpl = new Template
		for link in links do
			tpl.addn "* {link}"
		end
		return tpl
	end

	fun check_error do
		var error = api.last_error
		if error == null then return

		print "Error: {error.message}\n{error.body}"
		exit 1
	end
end

var prez = new Prez
prez.run

# TODO Show state and progress
# prez init 2020
	# set current year
# prez create team 2020
# prez create repo 2020
# prez create project 2020
# prez create issues 2020
# prez create members 2020
# prez create labels, milestones...
# prez config
# moz yearly create
# moz
# moz issues late
# moz issues late ping
# moz progress
# moz reassign issues
