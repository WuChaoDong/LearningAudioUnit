//
//  HomeController.m
//  LearningAudioUnitObjc
//
//  Created by oxape on 2020/10/30.
//

#import "HomeController.h"
#import "AudioUtilities.h"

@interface HomeController ()

@end

@implementation HomeController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [AudioUtilities printInfo];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:NSStringFromClass([self class])];
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([self class]) forIndexPath:indexPath];
    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = @"Loopback";
            break;
        case 1:
            cell.textLabel.text = @"MicrophoneAndFile";
            break;
        case 2:
            cell.textLabel.text = @"FileAndFile";
            break;
        default:
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.row) {
        case 0:
            [self performSegueWithIdentifier:@"Loopback" sender:self];
            break;
        case 1:
            [self performSegueWithIdentifier:@"MicrophoneAndFile" sender:self];
            break;
        case 2:
            [self performSegueWithIdentifier:@"FileAndFile" sender:self];
            break;
        default:
            break;
    }
}

@end
