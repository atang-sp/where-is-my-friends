#!/usr/bin/env node

/**
 * 本地化文件验证脚本
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

console.log('🔍 验证 where-is-my-friends 插件本地化文件');
console.log('================================');

const localesDir = path.join(__dirname, 'config', 'locales');
const files = [
    'client.en.yml',
    'client.zh_CN.yml', 
    'server.en.yml',
    'server.zh_CN.yml',
    'en.yml',
    'zh_CN.yml'
];

let hasErrors = false;

console.log('\n1. 检查文件是否存在');
console.log('--------------------------------');

files.forEach(file => {
    const filePath = path.join(localesDir, file);
    if (fs.existsSync(filePath)) {
        console.log(`✅ ${file}`);
    } else {
        console.log(`❌ ${file} - 文件不存在`);
        hasErrors = true;
    }
});

console.log('\n2. 检查 YAML 语法');
console.log('--------------------------------');

files.forEach(file => {
    const filePath = path.join(localesDir, file);
    if (fs.existsSync(filePath)) {
        try {
            const content = fs.readFileSync(filePath, 'utf8');
            const parsed = yaml.load(content);
            console.log(`✅ ${file} - YAML 语法正确`);
        } catch (error) {
            console.log(`❌ ${file} - YAML 语法错误: ${error.message}`);
            hasErrors = true;
        }
    }
});

console.log('\n3. 检查重复键');
console.log('--------------------------------');

function checkDuplicateKeys(obj, prefix = '') {
    const keys = new Set();
    const duplicates = [];
    
    for (const [key, value] of Object.entries(obj)) {
        const fullKey = prefix ? `${prefix}.${key}` : key;
        
        if (keys.has(key)) {
            duplicates.push(fullKey);
        } else {
            keys.add(key);
        }
        
        if (typeof value === 'object' && value !== null) {
            const nestedDuplicates = checkDuplicateKeys(value, fullKey);
            duplicates.push(...nestedDuplicates);
        }
    }
    
    return duplicates;
}

files.forEach(file => {
    const filePath = path.join(localesDir, file);
    if (fs.existsSync(filePath)) {
        try {
            const content = fs.readFileSync(filePath, 'utf8');
            const parsed = yaml.load(content);
            const duplicates = checkDuplicateKeys(parsed);
            
            if (duplicates.length === 0) {
                console.log(`✅ ${file} - 无重复键`);
            } else {
                console.log(`❌ ${file} - 发现重复键: ${duplicates.join(', ')}`);
                hasErrors = true;
            }
        } catch (error) {
            console.log(`❌ ${file} - 检查失败: ${error.message}`);
            hasErrors = true;
        }
    }
});

console.log('\n4. 检查翻译键一致性');
console.log('--------------------------------');

// 检查客户端和服务器端文件是否有相同的键
const clientZhCN = path.join(localesDir, 'client.zh_CN.yml');
const serverZhCN = path.join(localesDir, 'server.zh_CN.yml');

if (fs.existsSync(clientZhCN) && fs.existsSync(serverZhCN)) {
    try {
        const clientContent = fs.readFileSync(clientZhCN, 'utf8');
        const serverContent = fs.readFileSync(serverZhCN, 'utf8');
        
        const clientParsed = yaml.load(clientContent);
        const serverParsed = yaml.load(serverContent);
        
        const clientKeys = Object.keys(clientParsed.zh_CN.js.where_is_my_friends || {});
        const serverKeys = Object.keys(serverParsed.zh_CN.where_is_my_friends || {});
        
        const missingInServer = clientKeys.filter(key => !serverKeys.includes(key));
        const missingInClient = serverKeys.filter(key => !clientKeys.includes(key));
        
        if (missingInServer.length === 0 && missingInClient.length === 0) {
            console.log('✅ 客户端和服务器端翻译键一致');
        } else {
            console.log('⚠️  客户端和服务器端翻译键不一致:');
            if (missingInServer.length > 0) {
                console.log(`   服务器端缺失: ${missingInServer.join(', ')}`);
            }
            if (missingInClient.length > 0) {
                console.log(`   客户端缺失: ${missingInClient.join(', ')}`);
            }
        }
    } catch (error) {
        console.log(`❌ 检查翻译键一致性失败: ${error.message}`);
    }
}

console.log('\n5. 检查中英文一致性');
console.log('--------------------------------');

const clientEn = path.join(localesDir, 'client.en.yml');
const clientZhCN2 = path.join(localesDir, 'client.zh_CN.yml');

if (fs.existsSync(clientEn) && fs.existsSync(clientZhCN2)) {
    try {
        const enContent = fs.readFileSync(clientEn, 'utf8');
        const zhContent = fs.readFileSync(clientZhCN2, 'utf8');
        
        const enParsed = yaml.load(enContent);
        const zhParsed = yaml.load(zhContent);
        
        const enKeys = Object.keys(enParsed.en.js.where_is_my_friends || {});
        const zhKeys = Object.keys(zhParsed.zh_CN.js.where_is_my_friends || {});
        
        const missingInZh = enKeys.filter(key => !zhKeys.includes(key));
        const missingInEn = zhKeys.filter(key => !enKeys.includes(key));
        
        if (missingInZh.length === 0 && missingInEn.length === 0) {
            console.log('✅ 中英文翻译键一致');
        } else {
            console.log('⚠️  中英文翻译键不一致:');
            if (missingInZh.length > 0) {
                console.log(`   中文缺失: ${missingInZh.join(', ')}`);
            }
            if (missingInEn.length > 0) {
                console.log(`   英文缺失: ${missingInEn.join(', ')}`);
            }
        }
    } catch (error) {
        console.log(`❌ 检查中英文一致性失败: ${error.message}`);
    }
}

console.log('\n================================');
if (hasErrors) {
    console.log('❌ 发现本地化问题，需要修复');
} else {
    console.log('✅ 本地化文件验证通过，没有发现问题');
}
console.log('\n💡 建议：');
console.log('1. 如果验证通过，插件应该能正常支持中文界面');
console.log('2. 如果发现问题，请根据提示进行修复');
console.log('3. 修复后重启 Discourse 服务器'); 