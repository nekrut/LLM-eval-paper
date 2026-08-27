#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
    vcf_tbi=results/${sample}.vcf.gz.tbi
    bam_bai=results/${sample}.bam.bai
    raw1=data/raw/${sample}_1.fq.gz
    raw2=data/raw/${sample}_2.fq.gz
    ref=data/ref/chrM.fa

    if [ -f "$vcf_tbi" ] && [ -f "$bam_bai" ]; then
        t_vcf=$(stat -c %Y "$vcf_tbi")
        t_bam=$(stat -c %Y "$bam_bai")
        t_max=$t_vcf
        if (( t_bam > t_max )); then t_max=$t_bam; fi

        t_raw1=$(stat -c %Y "$raw1")
        t_raw2=$(stat -c %Y "$raw2")
        t_ref=$(stat -c %Y "$ref")

        if (( t_max >= t_raw1 && t_max >= t_raw2 && t_max >= t_ref )); then
            continue
        fi
    fi

    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ $THREADS -o results/${sample}.bam

    samtools index -@ $THREADS results/${sample}.bam

    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa \
        -o results/${sample}.vcf results/${sample}.bam

    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
done

collapsed=results/collapsed.tsv
t_collapsed=0
if [ -f "$collapsed" ]; then
    t_collapsed=$(stat -c %Y "$collapsed")
fi
t_latest=0
for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ -f "$vcf_gz" ]; then
        t=$(stat -c %Y "$vcf_gz")
        if (( t > t_latest )); then t_latest=$t; fi
    fi
done

if (( t_collapsed < t_latest )); then
    tmpfile=$(mktemp)
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmpfile"
    done
    header="sample\tchrom\tpos\tref\talt\taf"
    {
        printf "%s\n" "$header"
        cat "$tmpfile"
    } > "$collapsed"
    rm "$tmpfile"
fi

exit 0