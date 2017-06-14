#!/usr/bin/env python
# Copyright 2017, DELLEMC, Inc.
from jira import JIRA
import sys
import argparse
import common

class JIRAOperator(object):
    def __init__(self, server, username, password):
        # Initial jira 
        # set verify as false to get rid of requests.exceptions.SSLError: [Errno 1] _ssl.c:507: error:14090086:SSL routines:SSL3_GET_SERVER_CERTIFICATE:certificate verify failed
        options = {'server': server, 'verify': False}
        self.__jira = JIRA(options, basic_auth=(username, password))
        
    def search_issues(self, jql_str):
        issues = self.__jira.search_issues(jql_str)
        return issues


def parse_command_line(args):
    """
    Parse script arguments.
    :return: Parsed args for assignment
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--jira_server",
                        required=True,
                        help="The server url of jira",
                        action="store")
    parser.add_argument("--username",
                        required=True,
                        help="the username of jira",
                        action="store")
    parser.add_argument("--password",
                        required=True,
                        help="the password of jira",
                        action="store")

    parsed_args = parser.parse_args(args)
    return parsed_args

def query_fixed_bugs( jira_operator ):
    jql="project = RAC AND issuetype = Bug AND status = Done AND resolution in (Done) AND \"Affects Community\" = Yes AND resolved >= -8d ORDER BY cf[10506] ASC, priority DESC, key ASC, Rank ASC"                     
    return jira_operator.search_issues( jql )


def query_new_features( jira_operator ):
    jql="project = RI AND issuetype = Initiative AND status = Done AND \"Affects Community\" = Yes AND resolved >= -8d ORDER BY priority DESC, key ASC, Rank ASC"
    return jira_operator.search_issues( jql )

def query_open_bugs( jira_operator ):
    jql="project = RAC AND issuetype = Bug AND status in (\"To Do\", \"In Progress\", Backlog) AND priority in (P1, P2, P3, \"Not Set\", \"Needs Triage\") AND \"Affects Community\" = Yes ORDER BY key DESC"
    return jira_operator.search_issues( jql )



def main():
    # parse arguments
    args = parse_command_line(sys.argv[1:])
    jira_operator = JIRAOperator(args.jira_server,args.username,args.password)


    new_features  = query_new_features( jira_operator )
    fixed_bugs    =   query_fixed_bugs( jira_operator )
    open_bugs     =    query_open_bugs( jira_operator )

    f = open('release_notes.html','w')

    content= """<html>
    <head></head>
    <body><p>RackHD Release Notes</p></body>"""

    ############################################
    head_news="" #FIXME, should grab from a static web page
    content +="""
    <font size="7" color="blue"> Important Notes </font>
    <table style="width:100%" border="1">
    {0}
    </table>
    """.format(head_news)


    ############################################ 
    content +="""
    <font size="7" color="blue"> New features in this release </font>

    <table style="width:100%" border="1">
      <tr>
        <th>Key</th>
        <th>Summary</th> 
        <th>Created</th>
        <th>Resolved</th>
        <th>Reporter</th>
      </tr>
    """
    for issue in new_features :
        content +="""
          <tr>
             <td>{0}</td>
             <td>{1}</td>
             <td>{2}</td>
             <td>{3}</td>
             <td>{4}</td>
          </tr>
        """.format( issue.key, issue.fields.summary, str(issue.fields.created), str(issue.fields.resolutiondate), issue.fields.reporter.displayName )
    content +="""
    </table>"""
    ############################################

    ############################################ 
    content +="""
    <font size="7" color="blue">    Fixed Bugs in this release </font>

    <table style="width:100%" border="1">
      <tr>
        <th>Key</th>
        <th>Summary</th> 
        <th>Resolution</th> 
        <th>Resolved</th>
      </tr>
    """
    for issue in fixed_bugs :
        content +="""
          <tr>
             <td>{0}</td>
             <td>{1}</td>
             <td>{2}</td>
             <td>{3}</td>
          </tr>
        """.format( issue.key, issue.fields.summary, issue.fields.status, str(issue.fields.resolutiondate) )
    content +="""
    </table>"""
    ###############################################

    ############################################ 
    content +="""
    <font size="7" color="blue">Open Bugs</font>

    <table style="width:100%" border="1">
      <tr>
        <th>Key</th>
        <th>Summary</th> 
        <th>Created</th>
        <th>Status</th>
      </tr>
    """
    for issue in open_bugs :
        content +="""
          <tr>
             <td>{0}</td>
             <td>{1}</td>
             <td>{2}</td>
             <td>{3}</td>
          </tr>
        """.format( issue.key, issue.fields.summary, issue.fields.created , str(issue.fields.status) )
    content +="""
    </table>"""
    ###############################################


    content +="</html>"

    f.write(content)
    f.close()


    #common.write_parameters(args.parameters_file, report)

if __name__ == "__main__":
    main()
    sys.exit(0)
